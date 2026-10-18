# 14. Схемы данных

Формат — JSON (D-29). Все id — `snake_case` латиницей; отображаемые имена — ключи локализации.
Числа баланса — только здесь, не в коде.

## 14.1 Характеристики — `data/stats.json`
```json
{
  "main": ["strength", "agility", "speed", "endurance", "mental"],
  "additional": ["accuracy", "reaction", "luck", "stealth", "perception", "stix_care", "talent_facets"],
  "progress_threshold": { "formula": "10 * level" },
  "base_growth_per_general_level": 0.10,
  "experience_bonus": { "per_additional_sum": 10, "bonus": 0.01, "cap": 0.50 },
  "first_level_free_points": 50
}
```

## 14.2 Заражённые — `data/enemies/infected.json`
```json
{
  "id": "runner",
  "name_key": "ENEMY_RUNNER",
  "stage": 3,
  "level": [10, 20],
  "threat": "medium",
  "senses": { "hearing": 1.0, "sight": 0.7, "smell_blood": 0.8 },
  "move": { "walk": 1.8, "run": 6.5, "lunge_m": [5, 15] },
  "armor": { "head": 0, "torso": 0, "limbs": 0 },
  "weak_points": ["spore_sack", "head"],
  "pack": { "size": [2, 4], "follows": ["lottery", "stomper", "biter", "ruber", "elite"] },
  "evolves_to": "lottery",
  "spore_sack": "loot_runner",
  "xp": "medium"
}
```

Как сделано в M1 (задача 6) — поля, которые реально читает код:
```json
{
  "id": "runner", "stage": 3, "level": [10, 20], "threat": "medium",
  "body": { "radius": 0.38, "height": 1.85, "color": [0.72, 0.5, 0.35] },
  "hp": 150, "hp_per_level": 5,
  "move": { "walk": 1.8, "run": 6.5, "lunge": { "range": [5, 15], "speed": 14, "duration": 0.6, "cooldown": 4.0 } },
  "attack": { "damage": 18, "cooldown": 1.0, "range": 1.4 },
  "senses": { "sight": 26, "fov_deg": 160, "hearing": 1.2, "notice_close": 3.0 },
  "can_open_doors": true, "spore_sack": true,
  "ai": { "wander_radius": 20, "lose_sight_s": 12, "search_s": 14, "hunger_per_s": 0.002,
          "eat_per_s": 0.08, "hungry_at": 0.6, "smell_food": 35 }
}
```
Имена — `enemy_names` в `data/text/ru.json`. Броня по зонам и слабые места — задача 8.

## 14.3 Таблицы лута — `data/loot/*.json`
```json
{
  "id": "loot_runner",
  "rolls": [
    { "item": "sporan", "count": [4, 8], "chance": 1.0 },
    { "item": "grain",  "count": [1, 3], "chance": 1.0 },
    { "item": "nut",    "count": [0, 1], "chance": [0.1, 1.0] }
  ],
  "luck_scaling": { "chance_mult_per_100_luck": 0.05, "cap": 2.0 }
}
```
- `chance` диапазоном → интерполяция по уровню твари внутри стадии.
- M1: `luck_scaling` — общий на файл, таблицы лежат в `tables`; вместо `item` можно
  `one_of: [{ "item", "weight" }]`; `count` — сколько штук при удачном броске.

## 14.4 Предметы и трофеи — `data/items/*.json`
```json
{
  "id": "pearl_black",
  "category": "trophy",
  "weight_g": 2,
  "primary_inventory": true,
  "base_price": 2500,
  "consume": {
    "cooldown_group": "pearl", "cooldown_h": 36,
    "effects": [
      { "type": "stat_add", "stat": "mental", "value": [5, 15] },
      { "type": "stat_add", "stat": "talent_facets", "value": [1, 5] },
      { "type": "skill_chance", "by_skill_count": [0.20, 0.10, 0.05] }
    ],
    "risks": [ { "type": "become_quasi", "chance": 0.02, "chance_if_cooldown_violated": 0.35 } ]
  }
}
```

## 14.5 Умения — `data/skills/*.json`
```json
{
  "id": "fortune_smile",
  "kind": "buff",
  "mana_cost": 20,
  "cooldown_s": 86400,
  "effects": [
    { "type": "stat_mult", "stat": "luck", "value": 20, "duration_s": 8 }
  ],
  "scaling": [
    { "stat": "mental", "per": 10, "effect": "luck_mult", "add": 1 }
  ],
  "properties": [
    { "id": "fortune_immunity", "unlock": { "mental": 60 }, "effect": { "type": "immunity", "duration_s": 1.5 } }
  ],
  "blocked_on": ["cluster_disabled", "jammer"]
}
```

## 14.6 Кластеры — `data/world/clusters/*.json`
```json
{
  "id": "c_749_208_91",
  "template": "town_small_01",
  "type": "normal",
  "region": "steppe_mezhdurechye",
  "reload_h": [24, 336],
  "known_timer": false,
  "neighbors": ["c_749_208_92", "c_750_208_91"],
  "population_on_arrival": { "civilians": [80, 200], "immune_chance": 0.07 },
  "loot_profile": "town_civilian",
  "weather_source": "temperate_summer"
}
```

## 14.7 Шаблон кластера (метаданные сцены) — `data/world/templates/*.json`
```json
{
  "id": "town_small_01",
  "scene": "res://scenes/clusters/town_small_01.tscn",
  "size_m": [300, 300],
  "spawn_groups": ["street", "houses", "shop", "police"],
  "loot_points": 120,
  "stash_slots": 6,
  "resp_points": 2
}
```

## 14.8 Регион — `data/world/regions/*.json`
```json
{
  "id": "steppe_mezhdurechye",
  "threat": 1,
  "theme": "steppe",
  "clusters": ["…"],
  "stabs": ["three_pines"],
  "borders": [ { "to": "kotel", "via": ["c_…", "c_…"] } ],
  "factions": ["traders", "spiders_gang"]
}
```

## 14.9 Спутник — `data/npc/companions/*.json`
```json
{
  "id": "mechanic_cynic",
  "role": "technician",
  "skills": ["repair_vehicle"],
  "traits": ["cynic", "drinker"],
  "motive": "debt",
  "secret": "owes_bandits",
  "trust_start": 10,
  "betrayal": { "threshold": -50, "requires_offer": true },
  "lives": 6
}
```

## 14.10 Тексты — `data/text/ru.json` (D-35)
```json
{
  "stat_names": { "speed": "Скорость" },
  "log": {
    "stat_level_up_speed": [
      "Скорость — уровень {level}. Рекомендация: бегайте от тварей чаще. У вас хорошо получается.",
      "Скорость — уровень {level}. Убегать — тоже навык."
    ],
    "death": ["Жизнь {life} закончилась. Осталось жизней: {lives}."]
  }
}
```
- Для одного события — несколько вариантов текста, выбор случайный, без повторов подряд
  (`SystemLog.post(key, params)`).
- Особый вариант для конкретной характеристики: ключ `stat_level_up_<stat>`, иначе общий.

## 14.11 Скрытые характеристики — `data/hidden_traits.json`
```json
{ "id": "monster_hunter", "unlock": { "kill_elite_level": 100 }, "effect": { "type": "damage_vs", "tag": "elite", "mult": 1.05 } }
```
