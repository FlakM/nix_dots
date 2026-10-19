# Dwa gniazdka Shelly Plug M Gen3:
#   - "Sypialnia dzieci" — lampka, harmonogram 19:30 / 21:00
#   - "Biuro PC"         — pomiar zużycia PC + monitor i kosztu prądu
#
# Encje z integracji Shelly mają entity_id zależne od nazwy urządzenia
# ustawionej w aplikacji Shelly (Settings -> Device name). Zmiana nazwy
# urządzenia albo encji w Home Assistant wymaga dopasowania stałych niżej.
{ pkgs, ... }:
let
  # --- Encje dostarczane przez integrację Shelly ---
  # Nazwa urządzenia: "Sypialnia dzieci"
  kidsSwitch = "switch.sypialnia_dzieci";
  kidsPower = "sensor.sypialnia_dzieci_power";
  # Nazwa urządzenia: "Biuro PC"
  officeSwitch = "switch.biuro_pc";
  officePower = "sensor.biuro_pc_power";
  officeEnergy = "sensor.biuro_pc_energy";

  # --- Encje pomocnicze definiowane w tym pliku ---
  kidsPause = "input_boolean.sypialnia_dzieci_harmonogram_wstrzymany";
  kidsOnAt = "input_datetime.sypialnia_dzieci_wlacz";
  kidsOffAt = "input_datetime.sypialnia_dzieci_wylacz";
  price = "input_number.cena_pradu_za_kwh";
  officeEnergyToday = "sensor.biuro_pc_energia_dzis";
  officeEnergyMonth = "sensor.biuro_pc_energia_miesiac";
  officeCostHour = "sensor.biuro_pc_koszt_godzina";
  officeActive = "binary_sensor.biuro_pc_pracuje";
  officeRuntime = "sensor.biuro_pc_praca_dzis";

  # Koszt = energia (kWh) * cena (PLN/kWh). Waluta musi być kodem ISO (PLN),
  # bo tak wymaga device_class: monetary.
  costSensor = id: name: source: {
    inherit name;
    unique_id = id;
    default_entity_id = "sensor.${id}";
    unit_of_measurement = "PLN";
    device_class = "monetary";
    state_class = "total";
    icon = "mdi:cash";
    availability = "{{ is_number(states('${source}')) and is_number(states('${price}')) }}";
    state = "{{ ((states('${source}') | float(0)) * (states('${price}') | float(0))) | round(2) }}";
  };

  setupInstructions = ''
    ## Podłączenie gniazdek Shelly Plug M Gen3

    Nazwa urządzenia z aplikacji Shelly staje się `entity_id` w Home Assistant, więc musi się zgadzać z konfiguracją.

    1. W aplikacji Shelly połącz gniazdko z Wi-Fi i w **Ustawienia → Device name** wpisz dokładnie:
       - `Sypialnia dzieci` — lampka w sypialni dzieci,
       - `Biuro PC` — PC i monitor (np. na jednej listwie).
    2. Zostaw **External consumption type** jako `switch` (nie `light`).
    3. Home Assistant wykryje gniazdka w **Ustawienia → Urządzenia i usługi → Wykryte**. Jeśli nie, dodaj integrację **Shelly** i podaj adres IP gniazdka.
    4. Sprawdź, że istnieją encje `switch.sypialnia_dzieci`, `sensor.biuro_pc_power` i `sensor.biuro_pc_energy`.
    5. Domyślne wartości (19:30, 21:00, cena prądu) ustawią się same przy pierwszym starcie i możesz je potem zmieniać w tej zakładce.

    Jeśli `entity_id` wyjdą inne, zmień nazwy encji w Home Assistant albo dopasuj stałe na górze `hosts/odroid/smart-plugs.nix`.
  '';

  dashboard = (pkgs.formats.yaml { }).generate "smart-plugs.yaml" {
    title = "Gniazdka";
    views = [
      {
        title = "Gniazdka";
        path = "gniazdka";
        icon = "mdi:power-socket-eu";
        cards = [
          {
            type = "conditional";
            conditions = [
              {
                condition = "template";
                value_template = "{{ states('${kidsSwitch}') in ['unknown', 'unavailable'] or states('${officeSwitch}') in ['unknown', 'unavailable'] }}";
              }
            ];
            card = {
              type = "markdown";
              content = setupInstructions;
            };
          }
          {
            type = "grid";
            columns = 2;
            square = false;
            cards = [
              {
                type = "tile";
                entity = kidsSwitch;
                name = "Sypialnia dzieci";
                icon = "mdi:lamp";
                color = "amber";
              }
              {
                type = "tile";
                entity = officeSwitch;
                name = "Biuro PC (PC + monitor)";
                icon = "mdi:desktop-tower";
                tap_action = { action = "more-info"; };
                hold_action = {
                  action = "toggle";
                  confirmation = { text = "Wyłączyć gniazdko z PC?"; };
                };
              }
            ];
          }
          {
            type = "entities";
            title = "Sypialnia dzieci — światło";
            entities = [
              { entity = kidsSwitch; name = "Lampka"; }
              { entity = kidsPause; name = "Wstrzymaj harmonogram (np. wakacje)"; }
              { entity = kidsOnAt; name = "Włącz o"; }
              { entity = kidsOffAt; name = "Wyłącz o"; }
              { entity = kidsPower; name = "Moc (W)"; }
            ];
          }
          {
            type = "entities";
            title = "Biuro PC — bieżące";
            entities = [
              { entity = officeSwitch; name = "Gniazdko"; }
              { entity = officeActive; name = "PC pracuje"; }
              { entity = officePower; name = "Moc (W)"; }
              { entity = officeCostHour; name = "Koszt bieżący (PLN/h)"; }
              { entity = officeRuntime; name = "Czas pracy dziś"; }
            ];
          }
          {
            type = "entities";
            title = "Biuro PC — zużycie i koszt";
            entities = [
              { entity = officeEnergy; name = "Licznik energii (kWh)"; }
              { entity = officeEnergyToday; name = "Energia dziś (kWh)"; }
              { entity = officeEnergyMonth; name = "Energia w tym miesiącu (kWh)"; }
              { entity = "sensor.biuro_pc_koszt_dzis"; name = "Koszt dziś"; }
              { entity = "sensor.biuro_pc_koszt_miesiac"; name = "Koszt w tym miesiącu"; }
              { entity = price; name = "Cena prądu (PLN/kWh)"; }
            ];
          }
          {
            type = "history-graph";
            title = "Biuro PC — moc, ostatnie 24 h";
            hours_to_show = 24;
            entities = [{ entity = officePower; name = "Moc (W)"; }];
          }
        ];
      }
      {
        title = "Koszty PC";
        path = "koszty-pc";
        icon = "mdi:cash";
        cards = [
          {
            type = "statistics-graph";
            title = "Energia na dobę (kWh), ostatnie 30 dni";
            entities = [{ entity = officeEnergyToday; name = "Energia"; }];
            period = "day";
            days_to_show = 30;
            chart_type = "bar";
            stat_types = [ "change" ];
          }
          {
            type = "statistics-graph";
            title = "Koszt na dobę (PLN), ostatnie 30 dni";
            entities = [{ entity = "sensor.biuro_pc_koszt_dzis"; name = "Koszt"; }];
            period = "day";
            days_to_show = 30;
            chart_type = "bar";
            stat_types = [ "change" ];
          }
          {
            type = "statistics-graph";
            title = "Czas pracy na dobę (h), ostatnie 30 dni";
            entities = [{ entity = officeRuntime; name = "Czas pracy"; }];
            period = "day";
            days_to_show = 30;
            chart_type = "bar";
            stat_types = [ "change" ];
          }
          {
            type = "entities";
            title = "Podsumowanie";
            entities = [
              { entity = officeEnergy; name = "Licznik energii (kWh)"; }
              { entity = officeEnergyToday; name = "Energia dziś (kWh)"; }
              { entity = officeEnergyMonth; name = "Energia w tym miesiącu (kWh)"; }
              { entity = "sensor.biuro_pc_koszt_dzis"; name = "Koszt dziś"; }
              { entity = "sensor.biuro_pc_koszt_miesiac"; name = "Koszt w tym miesiącu"; }
              { entity = price; name = "Cena prądu (PLN/kWh)"; }
            ];
          }
          {
            type = "markdown";
            content = ''
              Koszt to energia (kWh) razy cena z `input_number.cena_pradu_za_kwh`. Wpisz stawkę z faktury (energia + dystrybucja, brutto), żeby liczby zgadzały się z rachunkiem.

              Gniazdko w biurze mierzy razem PC i monitor. Energię zobaczysz też w **Ustawienia → Dashboardy → Energia**.
            '';
          }
        ];
      }
    ];
  };
in
{
  services.home-assistant = {
    extraComponents = [ "shelly" "utility_meter" ];

    config = {
      input_boolean.sypialnia_dzieci_harmonogram_wstrzymany = {
        name = "Sypialnia dzieci — wstrzymaj harmonogram światła";
        icon = "mdi:calendar-remove";
      };
      input_datetime = {
        sypialnia_dzieci_wlacz = {
          name = "Sypialnia dzieci — włącz światło";
          has_date = false;
          has_time = true;
          icon = "mdi:weather-sunset-up";
        };
        sypialnia_dzieci_wylacz = {
          name = "Sypialnia dzieci — wyłącz światło";
          has_date = false;
          has_time = true;
          icon = "mdi:weather-sunset-down";
        };
      };
      input_number.cena_pradu_za_kwh = {
        name = "Cena prądu";
        min = 0;
        max = 5;
        step = 0.01;
        mode = "box";
        unit_of_measurement = "PLN/kWh";
        icon = "mdi:cash";
      };
      utility_meter = {
        biuro_pc_energia_dzis = {
          name = "Biuro PC energia dzis";
          unique_id = "biuro_pc_energia_dzis";
          source = officeEnergy;
          cycle = "daily";
        };
        biuro_pc_energia_miesiac = {
          name = "Biuro PC energia miesiac";
          unique_id = "biuro_pc_energia_miesiac";
          source = officeEnergy;
          cycle = "monthly";
        };
      };
      sensor = [
        {
          platform = "history_stats";
          name = "Biuro PC praca dzis";
          unique_id = "biuro_pc_praca_dzis";
          entity_id = officeActive;
          state = "on";
          type = "time";
          start = "{{ today_at('00:00') }}";
          end = "{{ now() }}";
        }
      ];
      template = [
        {
          sensor = [
            (costSensor "biuro_pc_koszt_dzis" "Biuro PC koszt dziś" officeEnergyToday)
            (costSensor "biuro_pc_koszt_miesiac" "Biuro PC koszt miesiąc" officeEnergyMonth)
            {
              name = "Biuro PC koszt godzina";
              unique_id = "biuro_pc_koszt_godzina";
              default_entity_id = officeCostHour;
              unit_of_measurement = "PLN";
              device_class = "monetary";
              icon = "mdi:cash-clock";
              availability = "{{ is_number(states('${officePower}')) and is_number(states('${price}')) }}";
              state = "{{ (((states('${officePower}') | float(0)) / 1000) * (states('${price}') | float(0))) | round(2) }}";
            }
          ];
          binary_sensor = [
            {
              name = "Biuro PC pracuje";
              unique_id = "biuro_pc_pracuje";
              default_entity_id = officeActive;
              device_class = "power";
              icon = "mdi:desktop-tower";
              availability = "{{ is_number(states('${officePower}')) }}";
              state = "{{ (states('${officePower}') | float(0)) > 30 }}";
            }
          ];
        }
      ];
      automation = [
        {
          id = "sypialnia_dzieci_swiatlo_wlacz";
          alias = "Sypialnia dzieci: włącz światło";
          description = "Włącza lampkę o godzinie z input_datetime, chyba że harmonogram jest wstrzymany.";
          mode = "single";
          triggers = [{ trigger = "time"; at = kidsOnAt; }];
          conditions = [
            { condition = "state"; entity_id = kidsPause; state = "off"; }
            { condition = "state"; entity_id = kidsSwitch; state = "off"; }
          ];
          actions = [{ action = "switch.turn_on"; target.entity_id = kidsSwitch; }];
        }
        {
          id = "sypialnia_dzieci_swiatlo_wylacz";
          alias = "Sypialnia dzieci: wyłącz światło";
          description = "Wyłącza lampkę o godzinie z input_datetime, chyba że harmonogram jest wstrzymany.";
          mode = "single";
          triggers = [{ trigger = "time"; at = kidsOffAt; }];
          conditions = [
            { condition = "state"; entity_id = kidsPause; state = "off"; }
            { condition = "state"; entity_id = kidsSwitch; state = "on"; }
          ];
          actions = [{ action = "switch.turn_off"; target.entity_id = kidsSwitch; }];
        }
        {
          id = "smart_plugs_wartosci_domyslne";
          alias = "Gniazdka: ustaw wartości domyślne";
          description = "Po starcie HA wypełnia cene prądu i godziny harmonogramu, jeśli nie zostały jeszcze ustawione. Dzięki temu zmiany z UI przetrwają restarty.";
          mode = "single";
          triggers = [{ trigger = "homeassistant"; event = "start"; }];
          actions = [
            {
              "if" = [{ condition = "numeric_state"; entity_id = price; below = 0.05; }];
              "then" = [{ action = "input_number.set_value"; target.entity_id = price; data.value = 0.8; }];
            }
            {
              "if" = [{ condition = "template"; value_template = "{{ states('${kidsOnAt}') in ['00:00:00', '00:00', '0', 'unknown', 'unavailable'] }}"; }];
              "then" = [{ action = "input_datetime.set_datetime"; target.entity_id = kidsOnAt; data.time = "19:30:00"; }];
            }
            {
              "if" = [{ condition = "template"; value_template = "{{ states('${kidsOffAt}') in ['00:00:00', '00:00', '0', 'unknown', 'unavailable'] }}"; }];
              "then" = [{ action = "input_datetime.set_datetime"; target.entity_id = kidsOffAt; data.time = "21:00:00"; }];
            }
          ];
        }
      ];
      lovelace.dashboards.smart-gniazdka = {
        mode = "yaml";
        filename = "${dashboard}";
        title = "Gniazdka";
        icon = "mdi:power-socket-eu";
        show_in_sidebar = true;
      };
    };
  };
}
