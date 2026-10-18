extends Node
## Глобальные сигналы игры. Сцены подписываются здесь, а не друг на друга.

@warning_ignore("unused_signal")
signal player_died(cause: String, lives_left: int)
@warning_ignore("unused_signal")
signal player_respawned
## Предметы, которые не влезли в инвентарь (крафт и т. п.), — сцена кладёт их под ноги героя.
@warning_ignore("unused_signal")
signal items_dropped(id: String, count: int)
@warning_ignore("unused_signal")
signal player_hurt(amount: float, source: String)
@warning_ignore("unused_signal")
signal infected_killed(enemy_id: String, level: int, position: Vector3)
## Шумовой импульс: source — ключ из data/noise.json, options — см. NoiseModel.radius() и from_hero.
@warning_ignore("unused_signal")
signal noise_made(source: String, position: Vector3, options: Dictionary)
## Герой попал по твари: result — из DamageModel.hit() (damage, zone, crit, armor_stopped)
## + attack ("light" / "heavy" / "ranged") и distance.
@warning_ignore("unused_signal")
signal player_hit(weapon_id: String, enemy_id: String, enemy_level: int, result: Dictionary, killed: bool)
## Стрела (или другой подбираемый боеприпас) упала в мире после выстрела.
@warning_ignore("unused_signal")
signal arrow_landed(item_id: String, position: Vector3)
## Герой вошёл в кластер (переход, возрождение на респе другого кластера).
@warning_ignore("unused_signal")
signal cluster_entered(cluster_id: String)
