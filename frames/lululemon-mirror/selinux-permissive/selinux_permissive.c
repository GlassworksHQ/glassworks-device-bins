/* selinux_permissive: minimal read-only backup helper module for lululemon Studio Mirror
 * stock 1.24.0 (kernel 3.10.49-perf-g4869d64961b, MSM8916, arm64).
 *
 * Sets kernel `selinux_enforcing = 0` in RAM for one boot so authorized USB ADB can read
 * raw /dev/block/mmcblk0p22 (system) and /dev/block/mmcblk0p19 (boot) while /system stays
 * mounted read-only. Never remounts /system rw and spawns no background daemon.
 *
 * Keep strictly outside the Glassworks repository (GPL-2.0 kernel module, Hard Rule 4).
 */
#define SEC(n) __attribute__((section(n), used))

struct this_module {
	unsigned char pad0[0x18];
	char name[56];
	unsigned char pad1[0x120 - 0x18 - 56];
	int (*init)(void);
	unsigned char pad2[0x210 - 0x120 - 8];
	void *exit;
	unsigned char pad3[0x220 - 0x210 - 8];
};

extern unsigned long kallsyms_lookup_name(const char *name);

static int sp_init(void)
{
	int *enforcing = (int *)kallsyms_lookup_name("selinux_enforcing");
	if (enforcing)
		*enforcing = 0;
	return 0;
}

static void sp_exit(void)
{
}

struct this_module __this_module SEC(".gnu.linkonce.this_module") = {
	.name = "selinux_permissive",
	.init = sp_init,
	.exit = sp_exit,
};

struct modversion_info {
	unsigned long crc;
	char name[56];
};

static const struct modversion_info versions[] SEC("__versions") = {
	{ 0xa5b7f7dd, "module_layout" },
	{ 0xe007de41, "kallsyms_lookup_name" },
};

static const char modinfo[] SEC(".modinfo") =
	"license=GPL\0"
	"depends=\0"
	"vermagic=3.10.49-perf-g4869d64961b SMP preempt mod_unload modversions aarch64\0";
