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
## Герой применил умение: effects — уже посчитанные SkillRules.effects() (сцена рисует и
## применяет свои: шум, подсветку, тварей).
@warning_ignore("unused_signal")
signal skill_used(skill_id: String, effects: Array)
## Случайность в пользу героя (D-76): kind — событие из data/luck.json или "immunity";
## at — где показать (Vector3.INF — над героем).
@warning_ignore("unused_signal")
signal luck_event(kind: String, at: Vector3)
## Пуля (умение): угроза уже летит в героя — from, параметры замедления — warn (danger_warn).
@warning_ignore("unused_signal")
signal danger_warned(from: Vector3, warn: Dictionary)
## Мешок твари брошен заранее (Нюх на мешок): ближайший труп в точке at получит этот лут.
@warning_ignore("unused_signal")
signal sack_prerolled(at: Vector3, loot: Dictionary)
## Знание карты изменилось (посещение, увиденная постройка, купленная карта, отметка) —
## карта и миникарта перерисовываются.
@warning_ignore("unused_signal")
signal map_changed
## Герой подобрал предметы (всплывающая строка «+ бинт ×2» у края экрана, 12.8).
@warning_ignore("unused_signal")
signal item_picked(item_id: String, count: int)
## Герой поставил капкан или приманку (задача 18): сцена создаёт предмет у его ног.
@warning_ignore("unused_signal")
signal place_requested(what: String)
