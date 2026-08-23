@tool
extends EditorExportPlugin

## 运行时 embedding 根目录（python/embeddings/<平台>/）。
const RUNTIME_BASE: String = "res://python/embeddings"
## SCons 依赖根目录（python/site-packages/），导出时同样按规则裁剪。
const SITE_PACKAGES_BASE: String = "res://python/site-packages"

## Unix 平台（linux/macos）布局相同：bin/ include/ lib/ share/。
## 仅列版本无关的条目；版本相关条目（lib/python3.14/... 等）
## 由 _versioned_trim_prefixes() 导出时动态生成，避免硬编码 Python 版本。
const UNIX_TRIMS: PackedStringArray = [
	"include",           # C 头文件（仅编译扩展需要）
	"share",             # man、terminfo
	"lib/pkgconfig",     # pkg-config 元数据
	"lib/itcl",          # Tcl 组件（仅 tkinter 使用）
	"lib/tcl", "lib/libtcl",   # Tcl 目录与动态库
	"lib/thread",        # Tcl 线程支持
	"lib/tk",            # Tk 目录
	"lib/libpython3.so",  # 未版本化链接桩（全静态构建无引用；版本化共享库由动态前缀覆盖）
	"bin/pip",           # pip / pip3 / pip3.14
	"bin/idle",          # IDLE 启动脚本
	"bin/pydoc",         # pydoc 启动脚本
	"bin/python3-config",  # 扩展编译配置
]

## 各平台运行库内的可裁剪目录（相对 embedding 根，运行时不需要的部分）。
const TRIM_DIRS: Dictionary = {
	"windows": [
		"include",
		"libs",
		"Scripts",   # pip 启动器（pip3.exe/pip3.14.exe）
		"Lib/site-packages",
		"Lib/ensurepip", "Lib/idlelib", "Lib/tkinter",
		"Lib/turtledemo", "Lib/unittest",
	],
	"linux": UNIX_TRIMS,
	"macos": UNIX_TRIMS,
}

## Windows Lib 死模块（importtime 实测未加载的纯 Python 模块）。
const WINDOWS_LIB_TRIMS: PackedStringArray = [
	"Lib/__phello__", "Lib/_pyrepl",
	"Lib/asyncio", "Lib/concurrent", "Lib/curses", "Lib/dbm",
	"Lib/email", "Lib/html", "Lib/http", "Lib/multiprocessing",
	"Lib/pydoc_data", "Lib/sqlite3", "Lib/tomllib",
	"Lib/urllib", "Lib/venv", "Lib/wsgiref", "Lib/xml",
	"Lib/xmlrpc", "Lib/zoneinfo",
	"Lib/__hello__.py", "Lib/_aix_support.py", "Lib/_android_support.py",
	"Lib/_apple_support.py", "Lib/_ios_support.py", "Lib/_osx_support.py",
	"Lib/_pydatetime.py", "Lib/_pydecimal.py", "Lib/_pyio.py",
	"Lib/antigravity.py", "Lib/argparse.py", "Lib/bdb.py", "Lib/calendar.py",
	"Lib/code.py", "Lib/colorsys.py", "Lib/compileall.py",
	"Lib/configparser.py", "Lib/contextvars.py", "Lib/cProfile.py",
	"Lib/csv.py", "Lib/decimal.py", "Lib/doctest.py", "Lib/filecmp.py",
	"Lib/fileinput.py", "Lib/fractions.py", "Lib/ftplib.py",
	"Lib/getopt.py", "Lib/getpass.py", "Lib/graphlib.py", "Lib/hmac.py",
	"Lib/imaplib.py", "Lib/ipaddress.py", "Lib/mailbox.py",
	"Lib/mimetypes.py", "Lib/modulefinder.py", "Lib/netrc.py",
	"Lib/nturl2path.py", "Lib/numbers.py", "Lib/pdb.py",
	"Lib/pickletools.py", "Lib/pkgutil.py", "Lib/plistlib.py",
	"Lib/poplib.py", "Lib/profile.py", "Lib/pstats.py", "Lib/pty.py",
	"Lib/py_compile.py", "Lib/pyclbr.py", "Lib/pydoc.py",
	"Lib/quopri.py", "Lib/rlcompleter.py", "Lib/runpy.py",
	"Lib/sched.py", "Lib/secrets.py", "Lib/selectors.py",
	"Lib/shelve.py", "Lib/smtplib.py", "Lib/socketserver.py",
	"Lib/ssl.py", "Lib/statistics.py", "Lib/stringprep.py",
	"Lib/symtable.py", "Lib/tabnanny.py", "Lib/tarfile.py",
	"Lib/this.py", "Lib/timeit.py", "Lib/trace.py",
	"Lib/tracemalloc.py", "Lib/tty.py", "Lib/turtle.py",
	"Lib/wave.py", "Lib/webbrowser.py", "Lib/zipapp.py",
	"Lib/_ast_unparse.py", "Lib/_markupbase.py", "Lib/_py_abc.py",
	"Lib/_pylong.py", "Lib/_strptime.py", "Lib/_threading_local.py",
	"Lib/gzip.py",
	"Lib/importlib/abc.py",
	"Lib/importlib/metadata/__init__.py", "Lib/importlib/metadata/_adapters.py",
	"Lib/importlib/metadata/_collections.py", "Lib/importlib/metadata/_functools.py",
	"Lib/importlib/metadata/_itertools.py", "Lib/importlib/metadata/_meta.py",
	"Lib/importlib/metadata/_text.py", "Lib/importlib/metadata/diagnose.py",
	"Lib/importlib/readers.py", "Lib/importlib/simple.py",
	"Lib/importlib/resources/__init__.py", "Lib/importlib/resources/_adapters.py",
	"Lib/importlib/resources/_common.py", "Lib/importlib/resources/_functional.py",
	"Lib/importlib/resources/_itertools.py", "Lib/importlib/resources/abc.py",
	"Lib/importlib/resources/readers.py", "Lib/importlib/resources/simple.py",
	"Lib/json/__main__.py", "Lib/json/tool.py",
	"Lib/logging/config.py", "Lib/logging/handlers.py",
	"Lib/pathlib/_local.py", "Lib/pathlib/types.py",
	"Lib/sre_compile.py", "Lib/sre_constants.py", "Lib/sre_parse.py",
	"Lib/string/templatelib.py", "Lib/sysconfig/__main__.py", "Lib/zipfile/__main__.py",
]

## Windows DLLs 死扩展（importtime 实测未加载的 .pyd/.dll）。
const WINDOWS_DLL_TRIMS: PackedStringArray = [
	"DLLs/_asyncio.pyd", "DLLs/_ctypes_test.pyd", "DLLs/_decimal.pyd",
	"DLLs/_elementtree.pyd", "DLLs/_multiprocessing.pyd", "DLLs/_overlapped.pyd",
	"DLLs/_remote_debugging.pyd", "DLLs/_sqlite3.pyd", "DLLs/_ssl.pyd",
	"DLLs/_testbuffer.pyd", "DLLs/_testcapi.pyd", "DLLs/_testclinic_limited.pyd",
	"DLLs/_testclinic.pyd", "DLLs/_testconsole.pyd", "DLLs/_testimportmultiple.pyd",
	"DLLs/_testinternalcapi.pyd", "DLLs/_testlimitedcapi.pyd", "DLLs/_testmultiphase.pyd",
	"DLLs/_testsinglephase.pyd", "DLLs/_tkinter.pyd", "DLLs/_zoneinfo.pyd",
	"DLLs/pyexpat.pyd", "DLLs/select.pyd", "DLLs/unicodedata.pyd", "DLLs/winsound.pyd",
	"DLLs/libssl-3-x64.dll", "DLLs/sqlite3.dll", "DLLs/tcl90.dll", "DLLs/tcl9tk90.dll",
	"DLLs/libcrypto-3-x64.dll",   # OpenSSL 加密库（仅 _ssl 引用，Godot 构建不加载 ssl）
	"DLLs/libtommath.dll",        # 大数运算库（_ssl 依赖，同上）
	"DLLs/zlib1.dll",             # zlib 运行时（_zstd/_hashlib 内置链接，实测无需）
]

## Unix stdlib 死模块（与 Windows Lib 同名单，importtime 实测一致；
## 含 sys.modules 快照实测为死的 _*.py 后备实现）。
const UNIX_STDLIB_TRIMS: PackedStringArray = [
	"__phello__", "_pyrepl", "asyncio", "concurrent", "curses", "dbm",
	"email", "html", "http", "multiprocessing", "pydoc_data", "sqlite3",
	"tomllib", "urllib", "venv", "wsgiref", "xml", "xmlrpc", "zoneinfo",
	"__hello__.py", "antigravity.py", "argparse.py", "bdb.py", "calendar.py",
	"code.py", "colorsys.py", "compileall.py", "configparser.py",
	"contextvars.py", "cProfile.py", "csv.py", "decimal.py", "doctest.py",
	"filecmp.py", "fileinput.py", "fractions.py", "ftplib.py", "getopt.py",
	"getpass.py", "graphlib.py", "hmac.py", "imaplib.py", "ipaddress.py",
	"mailbox.py", "mimetypes.py", "modulefinder.py", "netrc.py",
	"nturl2path.py", "numbers.py", "pdb.py", "pickletools.py", "pkgutil.py",
	"plistlib.py", "poplib.py", "profile.py", "pstats.py", "pty.py",
	"py_compile.py", "pyclbr.py", "pydoc.py", "quopri.py", "rlcompleter.py",
	"runpy.py", "sched.py", "secrets.py", "selectors.py", "shelve.py",
	"smtplib.py", "socketserver.py", "ssl.py", "statistics.py",
	"stringprep.py", "symtable.py", "tabnanny.py", "tarfile.py", "this.py",
	"timeit.py", "trace.py", "tracemalloc.py", "tty.py", "turtle.py",
	"wave.py", "webbrowser.py", "zipapp.py",
	"_ast_unparse.py", "_markupbase.py", "_py_abc.py", "_pylong.py",
	"_strptime.py", "_threading_local.py", "gzip.py",
	"importlib/abc.py", "importlib/metadata", "importlib/readers.py",
	"importlib/resources", "importlib/simple.py",
	"json/__main__.py", "json/tool.py",
	"logging/config.py", "logging/handlers.py",
	"pathlib/_local.py", "pathlib/types.py",
	"sre_compile.py", "sre_constants.py", "sre_parse.py",
	"string/templatelib.py", "sysconfig/__main__.py", "zipfile/__main__.py",
]

## Unix lib-dynload 死扩展（与 Windows 同名模块实测一致；.so 文件名带版本
## 后缀，以模块名作前缀匹配）。
const UNIX_DYNLOAD_TRIMS: PackedStringArray = [
	"_asyncio", "_ctypes_test", "_decimal", "_elementtree", "_multiprocessing",
	"_overlapped", "_remote_debugging", "_sqlite3", "_ssl", "_testbuffer",
	"_testcapi", "_testclinic", "_testclinic_limited", "_testconsole",
	"_testimportmultiple", "_testinternalcapi", "_testlimitedcapi",
	"_testmultiphase", "_testsinglephase", "_tkinter", "_zoneinfo",
	"pyexpat", "select", "unicodedata", "winsound",
	"_dbm",   # dbm 模块已裁剪，其 C 扩展无人引用
]

## 精确匹配的裁剪文件（避免前缀误伤，如 "bin/python" 不得命中 "bin/python3"）。
const EXACT_TRIMS: PackedStringArray = [
	"bin/python",     # 解释器冗余拷贝（仅保留 bin/python3）
	"pythonw.exe",    # GUI 入口启动器（工具仅使用 python.exe）
]

## site-packages（SCons）内的裁剪（相对 site-packages 根）。
const SITE_PACKAGES_TRIMS: PackedStringArray = [
	"SCons/Tool/docbook",   # 内嵌 XSLT 文档工具，Godot 构建不使用
	"scons-",               # 包元数据 scons-<版本>.dist-info（版本探测走 scons --version）
	"SCons/__main__.py",
	"SCons/compat/_scons_dbm.py",   # dbm 后备实现，无人引用
	"SCons/environmentvalues.py", "SCons/environmentvaluestest.py",   # 测试/遗留文件
	"SCons/exitfuncs.py",   # SCons 4.x 已弃用
	"SCons/Platform/aix.py", "SCons/Platform/bsd.py", "SCons/Platform/darwin.py",
	"SCons/Platform/hpux.py", "SCons/Platform/irix.py", "SCons/Platform/os2.py",
	"SCons/Platform/sunos.py",   # 本工具仅运行于 win32/linux/macos
	"SCons/Scanner/python.py",   # 仅 Tool/python 引用，Godot 不构建 Python 扩展
	"SCons/Tool/aixc++.py", "SCons/Tool/aixcc.py", "SCons/Tool/aixcxx.py",
	"SCons/Tool/aixf77.py", "SCons/Tool/aixlink.py",
	"SCons/Tool/applelink.py",   # Mac 框架链接，Godot macos 用默认 clang 工具链
	"SCons/Tool/bcc32.py", "SCons/Tool/cyglink.py", "SCons/Tool/dvi.py",
	"SCons/Tool/f03.py", "SCons/Tool/f08.py", "SCons/Tool/f77.py",
	"SCons/Tool/gettext_tool.py", "SCons/Tool/gettextcommon.py",
	"SCons/Tool/hpc++.py", "SCons/Tool/hpcc.py", "SCons/Tool/hpcxx.py", "SCons/Tool/hplink.py",
	"SCons/Tool/icc.py", "SCons/Tool/icl.py", "SCons/Tool/ifort.py",
	"SCons/Tool/ilink.py", "SCons/Tool/ilink32.py",
	"SCons/Tool/intelc.py",   # Intel 编译器，Godot 不使用
	"SCons/Tool/ipkg.py", "SCons/Tool/linkloc.py",
	"SCons/Tool/MSCommon/arch.py", "SCons/Tool/MSCommon/netframework.py",
	"SCons/Tool/MSCommon/README.rst",   # 文档
	"SCons/Tool/msgfmt.py", "SCons/Tool/msginit.py", "SCons/Tool/msgmerge.py",
	"SCons/Tool/mssdk.py", "SCons/Tool/mwcc.py", "SCons/Tool/mwld.py",
	"SCons/Tool/packaging",   # env.Package() 打包组件（Godot 不使用）
	"SCons/Tool/python.py",   # 运行 Python 脚本的 Builder（Godot 不使用）
	"SCons/Tool/rpm.py", "SCons/Tool/rpmutils.py",
	"SCons/Tool/sgiar.py", "SCons/Tool/sgic++.py", "SCons/Tool/sgicxx.py",
	"SCons/Tool/sgilink.py", "SCons/Tool/sgicc.py",
	"SCons/Tool/sunar.py", "SCons/Tool/sunc++.py", "SCons/Tool/suncc.py",
	"SCons/Tool/suncxx.py", "SCons/Tool/sunf77.py", "SCons/Tool/sunf90.py",
	"SCons/Tool/sunf95.py", "SCons/Tool/sunlink.py",
	"SCons/Tool/tlib.py", "SCons/Tool/xgettext.py",
	"SCons/Utilities/__init__.py", "SCons/Utilities/configurecache.py",
	"SCons/Utilities/sconsign.py",   # sconsign 命令行工具（本工具不经其读库）
]

var _target_platform: String = ""
var _versioned_trims: PackedStringArray = PackedStringArray()

func _get_name() -> String:
	return "GodotBuilderExportTrimmer"

## 从导出预设 features 识别目标平台，并生成版本相关的裁剪前缀。
func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_target_platform = _detect_platform(features)
	_versioned_trims = _versioned_trim_prefixes(_target_platform)

## 运行时 embedding 与 site-packages 均按规则裁剪，其余资源原样导出。
func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if _target_platform.is_empty():
		return
	if path.begins_with(RUNTIME_BASE):
		_trim_runtime(path)
	elif path.begins_with(SITE_PACKAGES_BASE):
		_trim_site_packages(path)

## 裁剪运行时 embedding：仅保留目标平台，删除未使用的模块与冗余文件。
func _trim_runtime(path: String) -> void:
	var rel: String = path.trim_prefix(RUNTIME_BASE).trim_prefix("/")
	var parts: PackedStringArray = rel.split("/")
	if parts.is_empty():
		return
	if parts[0] != _target_platform:
		skip()
		return
	if _is_trimmed(rel):
		skip()

## 判定运行时文件是否命中任一裁剪规则。
func _is_trimmed(rel: String) -> bool:
	if rel.contains("/__pycache__"):
		return true
	for trim: String in EXACT_TRIMS:
		if rel == trim:
			return true
	for trim: String in TRIM_DIRS.get(_target_platform, []):
		if rel.begins_with(trim):
			return true
	if _target_platform == "windows":
		for trim: String in WINDOWS_LIB_TRIMS + WINDOWS_DLL_TRIMS:
			if rel.begins_with(trim):
				return true
	for trim: String in _versioned_trims:
		if rel.begins_with(trim):
			return true
	return false

## 裁剪 site-packages：删除 SCons 未使用的大体积组件与运行时缓存。
func _trim_site_packages(path: String) -> void:
	var rel: String = path.trim_prefix(SITE_PACKAGES_BASE).trim_prefix("/")
	for trim: String in SITE_PACKAGES_TRIMS:
		if rel.begins_with(trim):
			skip()
			return
	if rel.contains("/__pycache__"):
		skip()

## 生成版本相关的裁剪前缀（stdlib 目录名含 Python 版本，如 lib/python3.14/...）。
## 导出时扫描 embedding 的 lib 目录动态生成；windows 无此类条目。
func _versioned_trim_prefixes(platform: String) -> PackedStringArray:
	if platform == "windows":
		return PackedStringArray()
	var dir: DirAccess = DirAccess.open(RUNTIME_BASE.path_join(platform).path_join("lib"))
	if dir == null:
		return PackedStringArray()
	var stdlib_dir: String = ""
	for entry: String in dir.get_directories():
		if entry.begins_with("python3."):
			stdlib_dir = entry
			break
	if stdlib_dir.is_empty():
		return PackedStringArray()
	var stdlib: String = "lib/%s" % stdlib_dir
	var version: String = stdlib_dir.trim_prefix("python")
	var trims: PackedStringArray = PackedStringArray([
		"%s/config-" % stdlib,            # config-3.14-<arch> 构建配置
		"%s/ensurepip" % stdlib,          # pip 安装引导
		"%s/idlelib" % stdlib,            # IDLE 编辑器
		"%s/tkinter" % stdlib,            # Tk GUI（无窗口工具不需要）
		"%s/turtledemo" % stdlib,         # turtle 示例
		"%s/unittest" % stdlib,           # 单元测试框架
		"%s/site-packages" % stdlib,      # 内置 pip
		"bin/python%s" % version,         # python3.14 解释器副本（仅保留 bin/python3）
		"bin/python%s-config" % version,  # python3.14-config（python3-config 已由 UNIX_TRIMS 覆盖）
		"lib/libpython%s.so" % version,   # 全静态构建，解释器不引用共享库（含 .so.1.0）
		"lib/libpython%s.dylib" % version,
	])
	for name: String in UNIX_STDLIB_TRIMS:
		trims.append("%s/%s" % [stdlib, name])
	for name: String in UNIX_DYNLOAD_TRIMS:
		trims.append("%s/lib-dynload/%s" % [stdlib, name])
	return trims

func _detect_platform(features: PackedStringArray) -> String:
	for feature: String in features:
		match feature.to_lower():
			"windows", "pc":
				return "windows"
			"linux", "x11":
				return "linux"
			"macos":
				return "macos"
	return ""