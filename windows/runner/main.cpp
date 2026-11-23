#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"
#include "win32_window.h"

static const wchar_t kMutexName[] =
    L"Global\\GrenadeHelper_SingleInstance_Mutex";
static const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
static const wchar_t kWindowTitle[] = L"Grenade Helper";
static const wchar_t kOverlayWindowTitle[] = L"Grenade Helper Overlay";

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
      EnumWindowsData* data = reinterpret_cast<EnumWindowsData*>(lParam);
      data->foundWindow = hwnd;
      return FALSE;
    }
  }
  return TRUE;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  const bool is_overlay =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--overlay") != command_line_arguments.end();

  HANDLE mutex = nullptr;
  if (!is_overlay) {
    mutex = ::CreateMutexW(nullptr, TRUE, kMutexName);
    if (mutex == nullptr) {
      return EXIT_FAILURE;
    }

    if (::GetLastError() == ERROR_ALREADY_EXISTS) {
      EnumWindowsData data = {nullptr};
      ::EnumWindows(EnumWindowsCallback, reinterpret_cast<LPARAM>(&data));

      if (data.foundWindow != nullptr) {
        ::SendMessageW(data.foundWindow, WM_SHOW_ME, 0, 0);
      }
      ::CloseHandle(mutex);
      return EXIT_SUCCESS;
    }

    if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
      CreateAndAttachConsole();
    }
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, is_overlay);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(is_overlay ? kOverlayWindowTitle : kWindowTitle, origin,
                     size)) {
    ::CoUninitialize();
    if (mutex != nullptr) {
      ::CloseHandle(mutex);
    }
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();

  if (mutex != nullptr) {
    ::CloseHandle(mutex);
  }
  return EXIT_SUCCESS;
}
