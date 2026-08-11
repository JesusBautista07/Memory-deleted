extends PickupObject
class_name WeaponItem
## Recogible de arma en el mundo. No añade ningún flujo nuevo de recogida:
## hereda tal cual el interact() de PickupObject, que ya se encarga de
## enviar el ObjectData (aquí, un WeaponData) al Inventory existente por el
## grupo "inventory". Esta clase solo existe para que WeaponManager pueda
## reconocer qué ObjectData del Inventory son armas (mismo patrón que
## DocumentItem/KeyItem/etc. ya usan para sus propios tipos).

func get_weapon_data() -> WeaponData:
	if object_data is WeaponData:
		return object_data
	return null
