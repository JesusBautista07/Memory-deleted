class_name PSXBoneRetargetMap
extends RefCounted
## Tabla de mapeo de nombres de huesos, reutilizable para CUALQUIER personaje
## del paquete Characters_psx.
##
## CONTEXTO:
## - Las animaciones universales ya existentes en el proyecto
##   (res://assets/animations/UAL1_Standard.glb, usadas por
##   SharedAnimationLibrary) usan nomenclatura de huesos estilo
##   "Unreal Mannequin" (hand_l, upperarm_l, thigh_l, spine_01, etc.).
## - Los modelos de Characters_psx (.fbx, exportados desde Mixamo) usan
##   nomenclatura "mixamorig:" (mixamorig:LeftHand, mixamorig:LeftArm,
##   mixamorig:LeftUpLeg, mixamorig:Spine, etc.).
##
## Esta tabla traduce Unreal -> Mixamo para poder reescribir, en tiempo de
## ejecución, los tracks de una animación pensada para el esqueleto Unreal
## de forma que apunten a los huesos reales del esqueleto Mixamo de un
## personaje PSX. Ver psx_animation_retargeter.gd.
##
## Verificado contra 4 modelos distintos del paquete (Character_01.fbx,
## Character_17_Police.fbx, Character_Female_01.fbx, Character_Monster.fbx):
## el esqueleto CORPORAL (cadera, columna, cuello, cabeza, brazos, piernas)
## es idéntico en nomenclatura en todos ellos. Lo que varía es el detalle
## de dedos (algunos personajes solo tienen el dedo índice, otros tienen
## los 5). Por eso esta tabla incluye el mapeo completo de dedos, pero
## PSXAnimationRetargeter omite automáticamente cualquier hueso que no
## exista en el esqueleto de destino, así que un personaje con menos dedos
## simplemente pierde esos tracks concretos sin que falle el resto.

const UNREAL_TO_MIXAMO := {
	"pelvis": "mixamorig:Hips",
	"spine_01": "mixamorig:Spine",
	"spine_02": "mixamorig:Spine1",
	"spine_03": "mixamorig:Spine2",
	"neck_01": "mixamorig:Neck",
	"Head": "mixamorig:Head",

	"clavicle_l": "mixamorig:LeftShoulder",
	"upperarm_l": "mixamorig:LeftArm",
	"lowerarm_l": "mixamorig:LeftForeArm",
	"hand_l": "mixamorig:LeftHand",
	"clavicle_r": "mixamorig:RightShoulder",
	"upperarm_r": "mixamorig:RightArm",
	"lowerarm_r": "mixamorig:RightForeArm",
	"hand_r": "mixamorig:RightHand",

	"thigh_l": "mixamorig:LeftUpLeg",
	"calf_l": "mixamorig:LeftLeg",
	"foot_l": "mixamorig:LeftFoot",
	"ball_l": "mixamorig:LeftToeBase",
	"ball_leaf_l": "mixamorig:LeftToe_End",
	"thigh_r": "mixamorig:RightUpLeg",
	"calf_r": "mixamorig:RightLeg",
	"foot_r": "mixamorig:RightFoot",
	"ball_r": "mixamorig:RightToeBase",
	"ball_leaf_r": "mixamorig:RightToe_End",

	# Dedos: no todos los personajes PSX los tienen todos (ver nota arriba).
	"index_01_l": "mixamorig:LeftHandIndex1",
	"index_02_l": "mixamorig:LeftHandIndex2",
	"index_03_l": "mixamorig:LeftHandIndex3",
	"index_04_leaf_l": "mixamorig:LeftHandIndex4",
	"thumb_01_l": "mixamorig:LeftHandThumb1",
	"thumb_02_l": "mixamorig:LeftHandThumb2",
	"thumb_03_l": "mixamorig:LeftHandThumb3",
	"thumb_04_leaf_l": "mixamorig:LeftHandThumb4",
	"middle_01_l": "mixamorig:LeftHandMiddle1",
	"middle_02_l": "mixamorig:LeftHandMiddle2",
	"middle_03_l": "mixamorig:LeftHandMiddle3",
	"middle_04_leaf_l": "mixamorig:LeftHandMiddle4",
	"ring_01_l": "mixamorig:LeftHandRing1",
	"ring_02_l": "mixamorig:LeftHandRing2",
	"ring_03_l": "mixamorig:LeftHandRing3",
	"ring_04_leaf_l": "mixamorig:LeftHandRing4",
	"pinky_01_l": "mixamorig:LeftHandPinky1",
	"pinky_02_l": "mixamorig:LeftHandPinky2",
	"pinky_03_l": "mixamorig:LeftHandPinky3",
	"pinky_04_leaf_l": "mixamorig:LeftHandPinky4",

	"index_01_r": "mixamorig:RightHandIndex1",
	"index_02_r": "mixamorig:RightHandIndex2",
	"index_03_r": "mixamorig:RightHandIndex3",
	"index_04_leaf_r": "mixamorig:RightHandIndex4",
	"thumb_01_r": "mixamorig:RightHandThumb1",
	"thumb_02_r": "mixamorig:RightHandThumb2",
	"thumb_03_r": "mixamorig:RightHandThumb3",
	"thumb_04_leaf_r": "mixamorig:RightHandThumb4",
	"middle_01_r": "mixamorig:RightHandMiddle1",
	"middle_02_r": "mixamorig:RightHandMiddle2",
	"middle_03_r": "mixamorig:RightHandMiddle3",
	"middle_04_leaf_r": "mixamorig:RightHandMiddle4",
	"ring_01_r": "mixamorig:RightHandRing1",
	"ring_02_r": "mixamorig:RightHandRing2",
	"ring_03_r": "mixamorig:RightHandRing3",
	"ring_04_leaf_r": "mixamorig:RightHandRing4",
	"pinky_01_r": "mixamorig:RightHandPinky1",
	"pinky_02_r": "mixamorig:RightHandPinky2",
	"pinky_03_r": "mixamorig:RightHandPinky3",
	"pinky_04_leaf_r": "mixamorig:RightHandPinky4",

	# NOTA: "root" (hueso auxiliar de movimiento raíz en el rig Unreal) no
	# tiene equivalente en el esqueleto Mixamo de Characters_psx (que usa
	# "Hips" como raíz). Se omite deliberadamente: PSXAnimationRetargeter
	# descarta cualquier track cuyo hueso no esté en este diccionario, así
	# que los tracks de "root" simplemente no se copian a la animación
	# retargeted. Si alguna animación de UAL1_Standard.glb depende de
	# movimiento en "root" para desplazarse (root motion), ese desplazamiento
	# NO se trasladará al personaje PSX; ver aviso al respecto en el reporte.
}
