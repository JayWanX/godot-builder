class_name SecretStore
extends RefCounted
## PCK 加密编译密钥（SCRIPT_AES256_ENCRYPTION_KEY）的简单加密存取。
##
## 存储：exe 旁 secrets.dat，内容为 XOR 加密后的 hex 文本。
## 加密：派生密钥 = sha256(机器唯一 ID + 可执行文件路径)，纯 GDScript 实现，无平台特定 API。
## 定位：混淆防裸眼（不追求高强度安全）；换机器/移动可执行文件后解密失败，视为未设置。

const FILE_NAME: String = "secrets.dat"

static var _derived_key: PackedByteArray = PackedByteArray()
static var _loaded: bool = false
static var _key_value: String = ""

## 读取当前密钥（解密失败或未设置时返回空串）。
static func get_key() -> String:
	_ensure_loaded()
	return _key_value

## 设置并持久化密钥；传空串表示清除。返回保存是否成功。
static func set_key(value: String) -> bool:
	_ensure_loaded()
	_key_value = value
	return _save()

## 强制重新从磁盘加载（构建开始前调用，确保最新值生效）。
static func reload() -> void:
	_loaded = false
	_ensure_loaded()

## 从磁盘加载密钥；文件缺失/损坏/解密失败时保持空串。
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_key_value = ""
	var data_path: String = AppData.executable_path.path_join(FILE_NAME)
	if not FileAccess.file_exists(data_path):
		return
	var content: String = FileAccess.get_file_as_string(data_path).strip_edges()
	if content.is_empty():
		return
	var encrypted: PackedByteArray = _hex_decode(content)
	if encrypted.is_empty():
		return
	var key_bytes: PackedByteArray = _get_derived_key()
	if key_bytes.size() < 32:
		return
	var decrypted: PackedByteArray = PackedByteArray()
	decrypted.resize(encrypted.size())
	for i in encrypted.size():
		decrypted[i] = encrypted[i] ^ key_bytes[i % key_bytes.size()]
	# 校验和（原值 sha256 前 8 字节）不匹配视为解密失败
	const CHECKSUM_SIZE: int = 8
	if decrypted.size() <= CHECKSUM_SIZE:
		return
	var raw: PackedByteArray = decrypted.slice(0, decrypted.size() - CHECKSUM_SIZE)
	var checksum: PackedByteArray = decrypted.slice(decrypted.size() - CHECKSUM_SIZE)
	if checksum != raw.hex_encode().sha256_buffer().slice(0, CHECKSUM_SIZE):
		return
	_key_value = raw.get_string_from_utf8()

## 写入磁盘：XOR 加密（含校验和）后 hex 编码保存。
static func _save() -> bool:
	var key_bytes: PackedByteArray = _get_derived_key()
	if key_bytes.size() < 32:
		return false
	const CHECKSUM_SIZE: int = 8
	var raw: PackedByteArray = _key_value.to_utf8_buffer()
	var payload: PackedByteArray = raw + raw.hex_encode().sha256_buffer().slice(0, CHECKSUM_SIZE)
	var encrypted: PackedByteArray = PackedByteArray()
	encrypted.resize(payload.size())
	for i in payload.size():
		encrypted[i] = payload[i] ^ key_bytes[i % key_bytes.size()]
	var file: FileAccess = FileAccess.open(
		AppData.executable_path.path_join(FILE_NAME), FileAccess.WRITE
	)
	if file == null:
		return false
	file.store_string(encrypted.hex_encode())
	file.close()
	return true

## 派生加密密钥：机器唯一 ID + 可执行文件路径的 sha256（绑定本机）。
static func _get_derived_key() -> PackedByteArray:
	if _derived_key.is_empty():
		var payload: String = OS.get_unique_id() + "\n" + AppData.executable_path
		_derived_key = payload.sha256_buffer()
	return _derived_key

## 十六进制字符串 → 字节数组（含非十六进制字符或奇数长度返回空数组）。
static func _hex_decode(hex: String) -> PackedByteArray:
	if hex.length() % 2 != 0:
		return PackedByteArray()
	var result: PackedByteArray = PackedByteArray()
	for i in range(0, hex.length(), 2):
		var byte: String = hex.substr(i, 2)
		if not "0123456789abcdefABCDEF".contains(byte[0]) or not "0123456789abcdefABCDEF".contains(byte[1]):
			return PackedByteArray()
		result.append(byte.hex_to_int())
	return result
