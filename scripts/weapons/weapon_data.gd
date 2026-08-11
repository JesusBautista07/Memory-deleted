extends ObjectData
class_name WeaponData
## Datos de un arma. Extiende ObjectData (sin modificarlo) para que las
## armas sean, para el Inventory existente, ObjectData normales y corriente
## — el Inventory no necesita saber que existen las armas. Solo añade los
## campos mínimos para mostrar el arma en primera persona. Deliberadamente
## NO incluye munición, daño ni retroceso: eso queda para un ticket futuro.

## Escena instanciable con el modelo en primera persona (ver
## scenes/weapons/WeaponViewModel_*.tscn). WeaponManager la instancia bajo
## su nodo WeaponMount al equipar esta arma.
@export var view_model_scene: PackedScene

## Identificador opcional de "hueco" de arma, libre para que un futuro
## sistema de equipo/HUD lo use (por ejemplo para mostrar un icono por
## slot). WeaponManager no lo usa todavía.
@export var weapon_slot: String = ""

## Desplazamiento del modelo en primera persona respecto a WeaponMount,
## para ajustar la posición de cada arma sin tener que tocar el script.
@export var holster_offset: Vector3 = Vector3.ZERO

## ---------------------------------------------------------------------
## Combate (Ticket 020C). Estos campos son solo CONFIGURACIÓN del arma
## (valores de diseño, ajustables desde el Inspector). El ESTADO real de
## munición en juego (cuánto queda en el cargador / en la reserva) no se
## guarda aquí: lo lleva WeaponCombat, para no mutar este recurso en
## runtime. Ver scripts/weapons/weapon_combat.gd.
## ---------------------------------------------------------------------

@export_group("Combate")
## Balas que caben en un cargador completo.
@export var magazine_size: int = 10
## Munición de reserva máxima (fuera del cargador) con la que empieza el arma.
@export var starting_reserve_ammo: int = 30
## Segundos mínimos entre disparo y disparo.
@export var fire_rate: float = 0.25
## Segundos que tarda una recarga completa.
@export var reload_time: float = 1.2
## Alcance máximo del RayCast de disparo.
@export var fire_range: float = 50.0
## Daño que este arma infligiría a un objetivo con take_damage(). Placeholder:
## no hay todavía ningún sistema de salud/IA que lo consuma.
@export var damage: float = 10.0

@export_group("Sonido (preparado, opcional)")
## Ids de AudioData ya registrados en AudioManager (grupo "audio_manager").
## Si están vacíos o no existen en el registro, WeaponCombat simplemente
## no reproduce nada: no rompe si el audio todavía no está preparado.
@export var fire_sound_id: String = ""
@export var empty_sound_id: String = ""
@export var reload_sound_id: String = ""
