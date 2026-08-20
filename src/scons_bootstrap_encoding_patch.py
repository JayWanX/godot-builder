## 编码补丁（Windows）：
## 1. PYTHONUTF8=1（UTF-8 模式）会让 subprocess 文本模式按 UTF-8 解码子进程输出，而
##    cl.exe/link.exe 输出为系统 OEM/ANSI 代码页（中文系统 GBK）→ 补丁 subprocess._text_encoding
##    按 OEM 代码页解码（覆盖 Godot MinGW 的 mySpawn / text=True 路径）。
## 2. SCons 默认 SPAWN 让子进程直接继承 stdout/stderr 句柄写原始 GBK 字节（MSVC 路径）→
##    在 fd 层用管道拦截并转码为 UTF-8，保证上层（Godot 管道读取）始终收到 UTF-8。

if sys.platform == 'win32' and getattr(sys.flags, 'utf8_mode', False):
	import subprocess as _sp
	
	def _sp_oem_encoding():
		try:
			import ctypes
			return 'cp%d' % ctypes.windll.kernel32.GetOEMCP()
		except Exception:
			return 'utf-8'
	
	_sp._text_encoding = _sp_oem_encoding

if sys.platform == 'win32':
	import os as _os
	import sys as _sys
	import threading as _th
	
	def _install_output_transcoder():
		try:
			_real_out = _os.dup(1)
			_real_err = _os.dup(2)
			_r1, _w1 = _os.pipe()
			_r2, _w2 = _os.pipe()
			_os.set_inheritable(_w1, True)
			_os.set_inheritable(_w2, True)
			_os.dup2(_w1, 1)
			_os.dup2(_w2, 2)
			_os.set_inheritable(1, True)
			_os.set_inheritable(2, True)
			_os.close(_w1)
			_os.close(_w2)
			
			def _pump(_r, _w):
				while True:
					try:
						_chunk = _os.read(_r, 65536)
					except OSError:
						break
					if not _chunk:
						break
					try:
						_text = _chunk.decode('utf-8')
					except UnicodeDecodeError:
						_text = _chunk.decode('oem', 'replace')
					try:
						_os.write(_w, _text.encode('utf-8'))
					except OSError:
						break
			
			_th.Thread(target=_pump, args=(_r1, _real_out)).start()
			_th.Thread(target=_pump, args=(_r2, _real_err)).start()
			
			def _flush_and_close():
				try:
					_sys.stdout.flush()
					_sys.stderr.flush()
				except Exception:
					pass
				try:
					_os.close(1)
				except OSError:
					pass
				try:
					_os.close(2)
				except OSError:
					pass
			
			# threading._shutdown 由解释器在 atexit 之前调用（Py3.14），普通 atexit 会死锁；
			# _register_atexit 在 join 非 daemon 线程前先执行，先关 fd 让泵线程收到 EOF。
			_th._register_atexit(_flush_and_close)
		except Exception:
			pass
	
	_install_output_transcoder()
	
	try:
		# Godot 的 silence_msvc（spawn_capture）用 sys.stdout.encoding 读回 cl/link 的
		# 临时输出文件，而 PYTHONUTF8=1 使该编码为 UTF-8 → GBK 内容被解码成乱码。
		# 把 stdio 编码改为 OEM 代码页（与 cl/link 输出一致），泵会负责转回 UTF-8。
		_sys.stdout.reconfigure(encoding='oem', errors='replace')
		_sys.stderr.reconfigure(encoding='oem', errors='replace')
	except Exception:
		pass
