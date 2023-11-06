local Translations = {
    error = {
        ["already_mission"] = "Již provádíš NPC misi",
        ["not_in_taxi"] = "Nejsi v taxíku",
        ["missing_meter"] = "Toto vozidlo nemá taxametr",
        ["no_vehicle"] = "Nejsi v vozidle",
        ["not_active_meter"] = "Taxametr není aktivní",
        ["no_meter_sight"] = "Žádný taxametr není v dohledu",
    },
    success = {},
    info = {
        ["person_was_dropped_off"] = "Osoba byla vysazena!",
        ["npc_on_gps"] = "NPC je označeno na tvém GPS",
        ["go_to_location"] = "Doveď NPC na určené místo",
        ["vehicle_parking"] = "[E] Parkování vozidla",
        ["job_vehicles"] = "[E] Pracovní vozidla",
        ["drop_off_npc"] = "[E] Vysadit NPC",
        ["call_npc"] = "[E] Zavolat NPC",
        ["blip_name"] = "Downtown Cab",
        ["taxi_label_1"] = "Standardní taxi",
        ["no_spawn_point"] = "Nepodařilo se najít místo pro zaparkování taxíku",
        ["taxi_returned"] = "Taxík zaparkován",
        ["request_taxi"] = "🚕 Objednat taxík",
        ["take_vehicle"] = "Vezmi naše "
    },
    menu = {
        ["taxi_menu_header"] = "Taxi vozidla",
        ["close_menu"] = "⬅ Zavřít menu",
        ['boss_menu'] = "Menu šéfa"
    }
}

if GetConvar('qb_locale', 'en') == 'cs' then
    Lang = Locale:new({
        phrases = Translations,
        warnOnMissing = true,
        fallbackLang = Lang,
    })
end
--translate by stepan_valic