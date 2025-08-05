//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <system_monitor/system_monitor_linux.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) system_monitor_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "SystemMonitorLinux");
  system_monitor_linux_register_with_registrar(system_monitor_registrar);
}
