#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

std::wstring LoadFluxidiWindowTitle() {
  wchar_t module_path[MAX_PATH] = {0};
  if (GetModuleFileNameW(nullptr, module_path, MAX_PATH) == 0) {
    return L"Fluxidi";
  }
  std::wstring path(module_path);
  const auto slash = path.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    path = path.substr(0, slash + 1) + L"fluxidi_window_title.txt";
  }
  FILE* file = nullptr;
  if (_wfopen_s(&file, path.c_str(), L"r, ccs=UTF-8") != 0 || file == nullptr) {
    return L"Fluxidi";
  }
  wchar_t buffer[256] = {0};
  const bool ok = fgetws(buffer, 256, file) != nullptr;
  fclose(file);
  if (!ok) {
    return L"Fluxidi";
  }
  std::wstring title(buffer);
  while (!title.empty() && (title.back() == L'\n' || title.back() == L'\r')) {
    title.pop_back();
  }
  return title.empty() ? L"Fluxidi" : title;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1680, 900);
  if (!window.Create(LoadFluxidiWindowTitle().c_str(), origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
