//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <ffmpeg_kit_flutter_new/f_fmpeg_kit_flutter_plugin.h>
#include <media_kit_libs_windows_audio/media_kit_libs_windows_audio_plugin_c_api.h>
#include <media_metadata/media_metadata_plugin_c_api.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  FFmpegKitFlutterPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FFmpegKitFlutterPlugin"));
  MediaKitLibsWindowsAudioPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MediaKitLibsWindowsAudioPluginCApi"));
  MediaMetadataPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MediaMetadataPluginCApi"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
}
