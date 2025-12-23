#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "win32_window.h"

// Single instance mutex name (unique identifier to avoid conflicts)
static const wchar_t kMutexName[] =
    L"Global\\GrenadeHelper_SingleInstance_Mutex";
// Window class name (Flutter runner class)
static const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
// Window title (used to find existing window)
static const wchar_t kWindowTitle[] = L"Grenade Helper";

// Callback for EnumWindows to find existing app window
struct EnumWindowsData {
  HWND foundWindow;
};

static BOOL CALLBACK EnumWindowsCallback(HWND hwnd, LPARAM lParam) {
  wchar_t className[256];
  wchar_t windowTitle[256];

  if (::GetClassNameW(hwnd, className, 256) > 0 &&
      ::GetWindowTextW(hwnd, windowTitle, 256) > 0) {
    if (wcscmp(className, kWindowClassName) == 0 &&
        wcscmp(windowTitle, kWindowTitle) == 0) {
      EnumWindowsData *data = reinterpret_cast<EnumWindowsData *>(lParam);
      data->foundWindow = hwnd;
      return FALSE; // Stop enumeration
    }
  }
  return TRUE; // Continue enumeration
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance check: try to create mutex
  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kMutexName);
  if (mutex == nullptr) {
    // Failed to create mutex, exit
    return EXIT_FAILURE;
  }

  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Another instance is already running
    // Use EnumWindows to find window even if hidden
    EnumWindowsData data = {nullptr};
    ::EnumWindows(EnumWindowsCallback, reinterpret_cast<LPARAM>(&data));

    if (data.foundWindow != nullptr) {
      // Send custom message to request window to show itself
      ::SendMessageW(data.foundWindow, WM_SHOW_ME, 0, 0);
    }
    // Release mutex and exit
    ::CloseHandle(mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Grenade Helper", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  // Release single instance mutex
  ::CloseHandle(mutex);
  return EXIT_SUCCESS;
}
