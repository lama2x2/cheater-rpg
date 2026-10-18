extends Node
## Глобальные сигналы игры. Сцены подписываются здесь, а не друг на друга.

@warning_ignore("unused_signal")
signal player_died(cause: String, lives_left: int)
