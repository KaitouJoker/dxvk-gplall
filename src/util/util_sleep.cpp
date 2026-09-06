#include "util_sleep.h"
#include "util_string.h"

#include "./log/log.h"

#include <thread>

// x86-specific pause macros to save energy during busy-waiting
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <immintrin.h>
#define CPU_PAUSE() _mm_pause()
#else
// Fallback
#define CPU_PAUSE() do {} while(0)
#endif

using namespace std::chrono_literals;

namespace dxvk {

  Sleep Sleep::s_instance;


  Sleep::Sleep() {

  }


  Sleep::~Sleep() {

  }

  void Sleep::initialize() {
    std::lock_guard lock(m_mutex);

    if (m_initialized.load())
      return;

    // Set sleepGranularity/SetTimerResolution
    // to 1ms by default on any CPU/OS
    initializePlatformSpecifics();

    // Set sleepThreshold to 2ms
    m_sleepThreshold = 2 * m_sleepGranularity;

    m_initialized.store(true, std::memory_order_release);
}


  void Sleep::initializePlatformSpecifics() {
#ifdef _WIN32
    HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");

    if (ntdll) {
      NtDelayExecution = reinterpret_cast<NtDelayExecutionProc>(
        ::GetProcAddress(ntdll, "NtDelayExecution"));
      auto NtQueryTimerResolution = reinterpret_cast<NtQueryTimerResolutionProc>(
        ::GetProcAddress(ntdll, "NtQueryTimerResolution"));
      auto NtSetTimerResolution = reinterpret_cast<NtSetTimerResolutionProc>(
        ::GetProcAddress(ntdll, "NtSetTimerResolution"));

      ULONG minRes, maxRes, curRes;

      // Wine's implementation of these functions is a stub as of 6.10, which is fine
      // since it uses select() in NtDelayExecution. This is only relevant for Windows.
      if (NtQueryTimerResolution && !NtQueryTimerResolution(&minRes, &maxRes, &curRes)) {
        // maxRes is the finest resolution supported by system (typically 5000 = 0.5ms on Win10/11)
        ULONG desiredRes = (maxRes > 0 && maxRes <= 10000) ? maxRes : 5000UL;

        if (NtSetTimerResolution && !NtSetTimerResolution(desiredRes, TRUE, &curRes)) {
          Logger::info(str::format("Setting timer interval to ", (double(curRes) / 10.0), " us"));
          m_sleepGranularity = TimerDuration(curRes > 0 ? curRes : desiredRes);
        } else {
          m_sleepGranularity = TimerDuration(1ms);
        }
      }
    } else {
      // Assume 1ms sleep granularity by default
      m_sleepGranularity = TimerDuration(1ms);
    }
#else
    // Assume 1ms sleep granularity by default
    m_sleepGranularity = TimerDuration(1ms);
#endif
  }


  Sleep::TimePoint Sleep::sleep(TimePoint t0, TimerDuration duration) {
    if (duration <= TimerDuration::zero())
      return t0;

    // if necessary, initialize function pointers and some values
    if (!m_initialized.load(std::memory_order_acquire)) 
        initialize();

    TimerDuration sleepThreshold = m_sleepThreshold;
    const TimePoint targetTime = t0 + duration;

    TimePoint t1 = t0;
    TimerDuration remaining = duration;

    while (remaining > sleepThreshold) {
      TimerDuration sleepDuration = remaining - sleepThreshold;

      // Try long sleep if sleepDuration exceeds the sleep threshold
      if (sleepDuration > sleepThreshold)
        systemSleep(sleepDuration);

      t1 = dxvk::high_resolution_clock::now();
      remaining = std::chrono::duration_cast<TimerDuration>(targetTime - t1);
      t0 = t1;
    }

    uint32_t loopCounter = 0;

    // Busy-wait until we have slept long enough
    while (remaining > TimerDuration::zero()) {
      // CPU arch-specific pause macros 
      // to save energy during busy-waiting
      CPU_PAUSE();

      // Intervals between wake up checks
      if (++loopCounter >= 256) {
        t1 = dxvk::high_resolution_clock::now();
        remaining = std::chrono::duration_cast<TimerDuration>(targetTime - t1);
        loopCounter = 0;
      }
    }

    return dxvk::high_resolution_clock::now();
}

  void Sleep::systemSleep(TimerDuration duration) {
#ifdef _WIN32
    if (NtDelayExecution) {
      LARGE_INTEGER ticks;
      ticks.QuadPart = -duration.count();

      NtDelayExecution(FALSE, &ticks);
    } else {
      std::this_thread::sleep_for(duration);
    }
#else
    std::this_thread::sleep_for(duration);
#endif
  }

}
