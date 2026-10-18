extends Node
## Глобальные сигналы игры. Сцены подписываются здесь, а не друг на друга.

@warning_ignore("unused_signal")
signal player_died(cause: String, lives_left: int)
@warning_ignore("unused_signal")
signal player_respawned
## Предметы, которые не влезли в инвентарь (крафт и т. п.), — сцена кладёт их под ноги героя.
@warning_ignore("unused_signal")
signal items_dropped(id: String, count: int)
