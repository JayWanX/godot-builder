#region 基础构建目标
target = "template_release"                                       # editor 构建带编辑器可执行文件；template_release 发布导出模板；template_debug 调试导出模板
arch = "x86_64"                                                   # auto 自动检测或手动指定
build_profile = "../project.gdbuild"                              # 功能裁剪配置（.gdbuild）文件路径，精细控制包含的类与模块
custom_modules_recursive = "no"                                   # 递归扫描自定义模块目录下的子文件夹以自动发现模块
modules_enabled_by_default = "no"                                 # no 时仅编译显式启用的模块（用于极致裁剪）
#endregion

#region 优化与性能
optimize = "size_extra"                                           # 编辑器默认 debug、模板默认 speed
lto = "full"                                                      # none 禁用；auto 自动；thin 轻量（低内存/耗时）；full 全局激进（提升性能但大幅增加链接内存与时间）
production = "yes"                                                # 移除调试辅助代码与断言，显著减小体积并提升性能；发布务必保持开启
#endregion

#region 功能开关
threads = "no"                                                    # 启用线程支持；几乎总是需要开启
deprecated = "no"                                                 # 包含已废弃/移除 API 的兼容代码；关闭可减小体积，新项目建议关闭
minizip = "no"                                                    # 启用基于 minizip 的 ZIP 压缩/解压功能（ZIP 功能的后端实现）
brotli = "no"                                                     # 启用 Brotli 解压缩及 WOFF2 字体支持
disable_3d = "yes"                                                # 彻底移除 3D 节点/渲染服务器，适合纯 2D 项目，大幅减小体积与内存
disable_physics_2d = "yes"                                        # 移除 2D 物理引擎；编辑器构建不建议禁用
disable_physics_3d = "yes"                                        # 移除内置 3D 物理；启用 Jolt 时可关闭以避免冗余
disable_navigation_2d = "yes"                                     # 移除 2D 导航网格生成与寻路
disable_navigation_3d = "yes"                                     # 移除 3D 导航网格生成与寻路
disable_xr = "yes"                                                # 全局移除所有 XR（AR/VR）接口与模块
engine_update_check = "no"                                        # 项目管理器自动检查新版本；通常关闭以减少网络请求
graphite = "no"                                                   # 启用 SIL Graphite 智能字体渲染支持
#endregion

#region 渲染与图形驱动
vulkan = "no"                                                     # 启用 Vulkan 渲染驱动（Forward+ / Mobile），最佳性能
use_volk = "no"                                                   # 通过 volk 动态加载 Vulkan 加载器，提升兼容性
accesskit = "no"                                                  # 启用屏幕阅读器支持驱动
angle = "no"                                                      # Windows 上将 OpenGL ES 转换为 DirectX，提高兼容性
sdl = "no"                                                        # 启用 SDL3 输入驱动
#endregion

#region Windows 平台特定
winrt = "no"                                                      # WinRT API（OneCore TTS 支持）
#endregion

#region 模块
module_freetype_enabled = "yes"                                   # 矢量字形栅格化字体渲染
module_gdscript_enabled = "yes"                                   # 核心脚本模块，几乎总是必需
module_glslang_enabled = "yes"                                    # GLSL→SPIR-V 着色器编译器，几乎所有渲染功能依赖
module_msdfgen_enabled = "yes"                                    # 多通道有向距离场字体（TextMesh）
module_regex_enabled = "yes"                                      # 模式匹配与字符串处理
module_svg_enabled = "yes"                                        # 矢量图形导入
module_text_server_fb_enabled = "yes"                             # 高级文本服务器不可用时的基础文本布局
#endregion