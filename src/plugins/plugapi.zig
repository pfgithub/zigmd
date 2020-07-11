pub fn setup(comptime Main: type) void {
    _ = struct {
        export fn zigmd_abi_version() callconv(.C) u32 {
            return 1;
        }
        export fn zigmd_plugin_info() callconv(.C) PluginInfo {
            return .{
                .name = Main.PluginName,
            };
        }
        export fn zigmd_plugin_init(plugin: *Plugin, env: *Env) callconv(.C) void {
            const commandProvider = @intToPtr(*CommandProvider, env.findProvider(0x97a0521a_1774_4804_9069_0388d57277bd));
            const notificationProvider = @intToPtr(*NotificationProvider, env.findProvider(0x5539e7ce_e0fa_4556_94fa_dcb56c633e27));
            commandProvider.addCommand(plugin, "Application: Demo Plugin", struct {
                fn a() callconv(.C) void {
                    notificationProvider.show("Demo!");
                }
            }.a);
            // this is terrible
            // this is an exact copy of atom
            // there is no reason to do this
        }
        export fn zigmd_plugin_deinit() callconv(.C) void {}
    };
}
