{ pkgs, ... }:
let
  availability = [
    { topic = "ebusd/global/running"; payload_available = "true"; payload_not_available = "false"; }
    { topic = "ebusd/global/signal"; payload_available = "true"; payload_not_available = "false"; }
  ];
  mqttSensor = id: name: topic: field: extra: {
    inherit name availability;
    unique_id = id;
    default_entity_id = "sensor.${id}";
    state_topic = "ebusd/${topic}";
    availability_mode = "all";
    value_template = "{{ value_json['${field}'].value }}";
    expire_after = 120;
  } // extra;
  temperature = { unit_of_measurement = "°C"; device_class = "temperature"; state_class = "measurement"; };
  counter = { state_class = "total_increasing"; expire_after = 3600; };
  historyStat = mode: label: kind: suffix: start: {
    platform = "history_stats";
    unique_id = "piec_${mode}_${suffix}";
    name = "Piec ${mode} ${label}";
    entity_id = "binary_sensor.piec_${mode}_aktywne";
    state = "on";
    type = kind;
    inherit start;
    end = "{{ now() }}";
    state_class = if suffix == "czas_dzisiaj" || suffix == "cykle_dzisiaj" then "total_increasing" else "measurement";
  };
  modeStats = mode: [
    (historyStat mode "czas dzisiaj" "time" "czas_dzisiaj" "{{ today_at('00:00') }}")
    (historyStat mode "cykle dzisiaj" "count" "cykle_dzisiaj" "{{ today_at('00:00') }}")
    (historyStat mode "czas tydzien" "time" "czas_tydzien" "{{ today_at('00:00') - timedelta(days=now().weekday()) }}")
    {
      platform = "history_stats";
      unique_id = "piec_${mode}_udzial_1h";
      name = "Piec ${mode} udzial 1h";
      entity_id = "binary_sensor.piec_${mode}_aktywne";
      state = "on";
      type = "ratio";
      duration.hours = 1;
      end = "{{ now() }}";
    }
  ];
  temperatureStat = source: suffix: characteristic: hours: {
    platform = "statistics";
    name = "Piec ${source} ${suffix}";
    unique_id = "piec_${source}_${suffix}";
    entity_id = "sensor.piec_${source}";
    state_characteristic = characteristic;
    max_age = { inherit hours; };
    precision = 1;
  };
  temperatureStats = source: [
    (temperatureStat source "minimum 24h" "value_min" 24)
    (temperatureStat source "srednia 24h" "mean" 24)
    (temperatureStat source "maksimum 24h" "value_max" 24)
  ];
  coTemperature = part: name: {
    inherit name;
    unique_id = "piec_co_${part}";
    default_entity_id = "sensor.piec_co_${part}";
    unit_of_measurement = "°C";
    device_class = "temperature";
    state_class = "measurement";
    availability = "{{ is_state('binary_sensor.piec_co_aktywne', 'on') and is_number(states('sensor.piec_${part}')) }}";
    state = "{{ states('sensor.piec_${part}') }}";
    attributes.sample_time = "{{ now().isoformat() }}";
  };
  modeTemplates = mode: label: status: {
    binary_sensor = [{
      name = "Piec ${label} aktywne";
      unique_id = "piec_${mode}_aktywne";
      default_entity_id = "binary_sensor.piec_${mode}_aktywne";
      availability = "{{ has_value('sensor.piec_status') }}";
      state = "{{ is_state('sensor.piec_status', '${status}') }}";
      icon = if mode == "co" then "mdi:radiator" else "mdi:water-boiler";
    }];
    sensor = [{
      name = "Piec ${label} sredni cykl dzisiaj";
      unique_id = "piec_${mode}_sredni_cykl_dzisiaj";
      default_entity_id = "sensor.piec_${mode}_sredni_cykl_dzisiaj";
      unit_of_measurement = "min";
      state_class = "measurement";
      availability = "{{ is_number(states('sensor.piec_${mode}_czas_dzisiaj')) and states('sensor.piec_${mode}_cykle_dzisiaj') | float(0) > 0 }}";
      state = "{% set cycles = states('sensor.piec_${mode}_cykle_dzisiaj') | float(0) %} {{ (60 * states('sensor.piec_${mode}_czas_dzisiaj') | float(0) / cycles) | round(2) if cycles > 0 else none }}";
    }
      {
        name = "Piec ${label} minuty dzisiaj";
        unique_id = "piec_${mode}_minuty_dzisiaj";
        default_entity_id = "sensor.piec_${mode}_minuty_dzisiaj";
        unit_of_measurement = "min";
        device_class = "duration";
        state_class = "total_increasing";
        availability = "{{ is_number(states('sensor.piec_${mode}_czas_dzisiaj')) }}";
        state = "{{ (60 * states('sensor.piec_${mode}_czas_dzisiaj') | float(0)) | round(2) }}";
      }];
  };
  entity = id: name: { entity = id; inherit name; };
  statusCard = {
    type = "markdown";
    title = "Status teraz";
    content = ''
      {% set status = states('sensor.piec_status') %}
      ## {{ {'standby': '🟢 Gotowość', 'heating': '🟠 CO — kaloryfery', 'heating hot water': '🔵 CWU — woda w kranach', 'circulating': '🟡 Obieg pompy', 'comfort': '🟣 Komfort CWU', 'low_water_pressure': '🔴 Niskie ciśnienie — sprawdź panel kotła', 'no_flame': '🔴 Brak płomienia — sprawdź panel kotła', 'unavailable': '🔴 Brak aktualnych danych', 'unknown': '⚪ Oczekiwanie na dane'}.get(status, '⚪ Tryb nierozpoznany: ' ~ status) }}
      {{ '🟢 Dane aktualne' if is_state('binary_sensor.piec_dane_aktualne', 'on') else '🔴 Dane nieaktualne' }} · {{ '🔥 Płomień wykryty' if is_state('binary_sensor.piec_plomien_aktywne', 'on') else ('⚫ Płomień wyłączony' if is_state('binary_sensor.piec_plomien_aktywne', 'off') else '⚪ Brak danych o płomieniu') }}

      **Zasilanie:** {{ states('sensor.piec_zasilanie') }} °C · **Powrót:** {{ states('sensor.piec_powrot') }} °C
    '';
  };
  graph = title: entities: { type = "history-graph"; inherit title entities; hours_to_show = 12; };
  temperatureEntities = [
    { entity = "sensor.piec_zasilanie"; name = "Zasilanie"; color = "#e76f51"; }
    { entity = "sensor.piec_powrot"; name = "Powrót"; color = "#457b9d"; }
  ];
  temperatureGraph = title: period: days: stats: entities: {
    type = "statistics-graph";
    inherit title period entities;
    days_to_show = days;
    chart_type = "line";
    stat_types = stats;
  };
  temperatureSummary = source: title: {
    type = "entities";
    inherit title;
    entities = [
      (entity "sensor.piec_${source}_minimum_24h" "Minimum")
      (entity "sensor.piec_${source}_srednia_24h" "Średnia próbek")
      (entity "sensor.piec_${source}_maksimum_24h" "Maksimum")
    ];
  };
  dailyGraph = title: entities: {
    type = "statistics-graph";
    inherit title entities;
    days_to_show = 7;
    period = "day";
    chart_type = "bar";
    stat_types = [ "change" ];
  };
  modeView = mode: label: {
    title = label;
    path = mode;
    icon = if mode == "co" then "mdi:radiator" else "mdi:water";
    cards = [
      {
        type = "entities";
        title = "${label} — od rozpoczecia monitoringu";
        entities = [
          (entity "binary_sensor.piec_${mode}_aktywne" "Aktywne teraz")
          (entity "sensor.piec_${mode}_minuty_dzisiaj" "Czas dzisiaj (min)")
          (entity "sensor.piec_${mode}_cykle_dzisiaj" "Epizody dzisiaj")
          (entity "sensor.piec_${mode}_sredni_cykl_dzisiaj" "Średni epizod (min)")
          (entity "sensor.piec_${mode}_udzial_1h" "Aktywność w ostatniej godzinie (%)")
          (entity "sensor.piec_${mode}_czas_tydzien" "Czas w tym tygodniu (h)")
        ];
      }
      (graph "${label} — kiedy pracuje" [ (entity "binary_sensor.piec_${mode}_aktywne" label) ])
      (dailyGraph "${label} — czas pracy na dobę (min)" [ "sensor.piec_${mode}_minuty_dzisiaj" ])
      (dailyGraph "${label} — epizody na dobe" [ "sensor.piec_${mode}_cykle_dzisiaj" ])
    ] ++ (if mode == "co" then [
      (graph "CO — temperatura obiegu kotła, 12 h" [
        (entity "sensor.piec_zasilanie" "Zasilanie")
        (entity "sensor.piec_powrot" "Powrot")
      ])
      (graph "CO — roznica temperatur podczas ogrzewania" [ (entity "sensor.piec_co_delta_t" "Delta T") ])
      (temperatureSummary "co_zasilanie" "Zasilanie tylko podczas CO — 24 h")
      (temperatureSummary "co_powrot" "Powrót tylko podczas CO — 24 h")
      (temperatureSummary "co_delta_t" "Delta T tylko podczas CO — 24 h")
    ] else [
      {
        type = "markdown";
        content = "CWU jest podgrzewane przepływowo, bez zewnętrznego zasobnika. Epizod oznacza wykryty tryb CWU kotła, nie pojedyncze mycie rąk. Krótkie pobory mogą umknąć próbkowaniu. Rejestr 6147 ma sprzeczne opisy (nastawa/pomiar) i nie jest potwierdzoną temperaturą w kranie. Litry i kWh wymagają potwierdzonego pomiaru.";
      }
      (graph "CWU — rejestr 6147, znaczenie niepotwierdzone" [ "sensor.piec_cwu_6147" ])
    ]);
  };
  dashboard = (pkgs.formats.yaml { }).generate "heating-monitoring.yaml" {
    title = "Piec";
    views = [
      {
        title = "Przegląd";
        path = "overview";
        icon = "mdi:fire";
        cards = [
          statusCard
          {
            type = "markdown";
            content = "## Ariston Clas X 24 CF EU\nKociol dwufunkcyjny: **CO = kaloryfery**, **CWU = przeplywowa woda w kranach**. Monitoring tylko do odczytu. Czasy dotycza trybu kotla; nie sa dokladnym pomiarem spalania gazu. Historia szczegolowa: 30 dni; statystyki dlugoterminowe od uruchomienia. Pierwszy dzien/tydzien jest niepelny.";
          }
          {
            type = "entities";
            title = "Teraz";
            entities = [
              "sensor.piec_tryb"
              "binary_sensor.piec_dane_aktualne"
              "sensor.piec_zasilanie"
              "sensor.piec_powrot"
              "sensor.piec_co_delta_t"
              "switch.piec_ogrzewanie_ta1"
            ];
          }
          {
            type = "tile";
            entity = "switch.piec_ogrzewanie_ta1";
            name = "Ogrzewanie (TA1)";
            color = "red";
            vertical = true;
          }
          (graph "CO i CWU — ostatnie 12 godzin" [
            (entity "binary_sensor.piec_co_aktywne" "Kaloryfery")
            (entity "binary_sensor.piec_cwu_aktywne" "Woda w kranach")
            (entity "binary_sensor.piec_plomien_aktywne" "Wykryty płomień")
          ])
          (temperatureGraph "Temperatury obiegu — trend z ostatnich 24 h" "5minute" 1 [ "mean" ] temperatureEntities)
          {
            type = "statistics-graph";
            title = "Czas CO i CWU — minuty pracy w przedziałach 5 min";
            entities = [
              (entity "sensor.piec_co_minuty_dzisiaj" "CO")
              (entity "sensor.piec_cwu_minuty_dzisiaj" "CWU")
            ];
            period = "5minute";
            days_to_show = 1;
            chart_type = "bar";
            stat_types = [ "change" ];
          }
          (dailyGraph "Czas CO i CWU na dobę (min)" [
            (entity "sensor.piec_co_minuty_dzisiaj" "CO")
            (entity "sensor.piec_cwu_minuty_dzisiaj" "CWU")
          ])
          (dailyGraph "Epizody CO i CWU na dobe" [
            (entity "sensor.piec_co_cykle_dzisiaj" "CO")
            (entity "sensor.piec_cwu_cykle_dzisiaj" "CWU")
          ])
        ];
      }
      {
        title = "Temperatury";
        path = "temperatures";
        icon = "mdi:thermometer-lines";
        cards = [
          {
            type = "grid";
            columns = 2;
            square = false;
            cards = [
              { type = "tile"; entity = "sensor.piec_zasilanie"; name = "Zasilanie teraz"; color = "deep-orange"; }
              { type = "tile"; entity = "sensor.piec_powrot"; name = "Powrót teraz"; color = "blue"; }
              { type = "tile"; entity = "sensor.piec_co_delta_t"; name = "Delta T podczas CO"; }
              { type = "tile"; entity = "sensor.piec_zasilanie_zakres_1h"; name = "Wahania zasilania — 1 h"; }
            ];
          }
          {
            type = "vertical-stack";
            cards = [
              ((graph "Szczegóły temperatur — ostatnie 2 h" [
                (entity "sensor.piec_zasilanie" "Zasilanie")
                (entity "sensor.piec_powrot" "Powrót")
              ]) // { hours_to_show = 2; })
              ((graph "Tryb kotła w tym samym czasie" [
                (entity "binary_sensor.piec_co_aktywne" "CO")
                (entity "binary_sensor.piec_cwu_aktywne" "CWU")
              ]) // { hours_to_show = 2; })
            ];
          }
          (temperatureSummary "zasilanie" "Zasilanie — ostatnie 24 h, wszystkie tryby")
          (temperatureSummary "powrot" "Powrót — ostatnie 24 h, wszystkie tryby")
          {
            type = "entities";
            title = "Najciekawsze punkty temperatury";
            entities = [
              (entity "sensor.piec_zasilanie_szczyt_24h" "Kiedy zasilanie było najcieplejsze")
              (entity "sensor.piec_powrot_szczyt_24h" "Kiedy powrót był najcieplejszy")
              (entity "sensor.piec_zasilanie_zakres_1h" "Zakres wahań zasilania — 1 h")
              (entity "sensor.piec_powrot_zakres_1h" "Zakres wahań powrotu — 1 h")
              (entity "sensor.piec_co_delta_t_srednia_24h" "Średnia Delta T podczas CO — 24 h")
            ];
          }
          (temperatureGraph "Zasilanie — minimum, średnia i maksimum co 5 min" "5minute" 1 [ "min" "mean" "max" ] [ (entity "sensor.piec_zasilanie" "Zasilanie") ])
          (temperatureGraph "Powrót — minimum, średnia i maksimum co 5 min" "5minute" 1 [ "min" "mean" "max" ] [ (entity "sensor.piec_powrot" "Powrót") ])
          (temperatureGraph "CO — Delta T w czasie" "5minute" 1 [ "min" "mean" "max" ] [ (entity "sensor.piec_co_delta_t" "Delta T") ])
          (temperatureGraph "Trend tygodniowy — średnie godzinowe" "hour" 7 [ "mean" ] temperatureEntities)
          {
            type = "markdown";
            content = "**Jak czytać:** wzrost zasilania pokazuje nagrzewanie obiegu kotła; różnica z powrotem pomaga analizować odbiór ciepła podczas CO. Powtarzające się skoki wraz z krótkimi epizodami mogą wskazywać taktowanie.\n\nTe czujniki mierzą **obieg kotła** także podczas podgrzewania CWU, nie wodę wypływającą z kranu. Statystyki na zakładce CO odrzucają inne tryby. Minimum/średnia/maksimum obejmują dostępne próbki z ostatnich 24 h, początkowo krótszy okres. Średnia próbek nie jest dokładną średnią czasową; Delta T nie mierzy sprawności. Szczyty są ograniczone rozdzielczością odczytów. Wykresy 5-minutowe pojawiają się po pierwszym przeliczeniu, godzinowe po zakończeniu godziny.";
          }
        ];
      }
      (modeView "co" "Kaloryfery — CO")
      (modeView "cwu" "Woda w kranach — CWU")
      {
        title = "Diagnostyka";
        path = "diagnostics";
        icon = "mdi:chart-line";
        cards = [
          {
            type = "entities";
            title = "Liczniki kotla — odczyt co 15 minut";
            entities = [
              "sensor.piec_licznik_co_surowy"
              "sensor.piec_licznik_cwu_surowy"
              "sensor.piec_licznik_zaplonow"
              "sensor.piec_licznik_pompy_surowy"
              "sensor.piec_licznik_zaworu"
            ];
          }
          (dailyGraph "Przyrost rejestru zapłonów na dobę" [ "sensor.piec_licznik_zaplonow" ])
          (graph "Modulacja — surowy rejestr, skala niepotwierdzona" [ "sensor.piec_modulacja_surowa" ])
          {
            type = "entities";
            title = "Jakosc monitoringu";
            entities = [ "sensor.piec_dostepnosc_dzisiaj" "binary_sensor.piec_dane_aktualne" ];
          }
          {
            type = "entities";
            title = "Płomień — zaobserwowane próbki, nie pomiar gazu";
            entities = [
              "binary_sensor.piec_plomien_aktywne"
              (entity "sensor.piec_plomien_czas_dzisiaj" "Czas płomienia dzisiaj (h)")
              (entity "sensor.piec_plomien_cykle_dzisiaj" "Zaobserwowane epizody płomienia")
            ];
          }
          {
            type = "markdown";
            content = "**Ocena pracy CO:** obserwuj długość epizodów, przyrost rejestru zapłonów oraz zasilanie/powrót i Delta T. Krótkie cykle mogą wskazywać taktowanie, ale nie dowodzą usterki. Przerwy dostępności mogą rozdzielać jeden epizod na kilka. Temperatury są odczytywane kolejno; Delta T podczas przełączenia trybu może być chwilowo zniekształcona i nie jest sprawnością.\n\n**Liczniki:** skala czasu CO/CWU/pompy wymaga porównania z menu kotła — pokazujemy surowe wartości bez przypisywania godzin. Modulacja również ma niepotwierdzoną jednostkę.\n\n**Gaz:** nie mamy potwierdzonego licznika m³ ani przepływomierza gazu. Czas płomienia i modulacja nie są pomiarem zużycia. Rejestr 6847 ma sprzeczne opisy (moc/przepływ CWU), a 6147 — nastawa/pomiar CWU. Nie wyliczamy na ich podstawie kWh, m³ ani sprawności. Rzeczywisty pomiar wymaga odczytu gazomierza lub potwierdzonego sensora przepływu gazu.";
          }
        ];
      }
    ];
  };
in
{
  services.home-assistant = {
    extraComponents = [ "template" "history" "history_stats" "statistics" "rest" ];
    config = {
      history = { };
      rest = [
        {
          resource = "http://192.168.0.244/api/v1/pin";
          scan_interval = 5;
          sensor = [{
            name = "piec_pin6";
            unique_id = "piec_pin6";
            value_template = "{{ value_json.io['6'].value }}";
          }];
        }
      ];
      lovelace.dashboards.heating-monitor = {
        mode = "yaml";
        filename = "${dashboard}";
        title = "Piec";
        icon = "mdi:radiator";
        show_in_sidebar = true;
      };
      mqtt.sensor = [
        (mqttSensor "piec_status" "Piec status" "boiler/boiler_status" "boilerstatus" { expire_after = 120; })
        (mqttSensor "piec_zasilanie" "Piec zasilanie" "boiler/LWT_temp" "0" (temperature // { force_update = true; }))
        (mqttSensor "piec_powrot" "Piec powrot" "boiler/EWT_temp" "0" (temperature // { force_update = true; }))
        (mqttSensor "piec_modulacja_surowa" "Piec modulacja surowa" "boiler/boiler_current_modulation" "0" { state_class = "measurement"; })
        (mqttSensor "piec_cwu_6147" "Piec CWU 6147 — dekoder community" "energymgr/dhw_current_target_temp" "0" { state_class = "measurement"; expire_after = 600; })
        (mqttSensor "piec_licznik_co_surowy" "Piec licznik CO — surowy" "boiler/hours_burner_on_CH" "0" counter)
        (mqttSensor "piec_licznik_cwu_surowy" "Piec licznik CWU — surowy" "boiler/hours_burner_on_DHW" "0" counter)
        (mqttSensor "piec_licznik_zaplonow" "Piec licznik zaplonow" "boiler/ignition_cycles" "0" counter)
        (mqttSensor "piec_licznik_pompy_surowy" "Piec licznik pompy — surowy" "boiler/hours_pump_on" "0" counter)
        (mqttSensor "piec_licznik_zaworu" "Piec licznik zaworu" "boiler/diverter_cycles" "0" counter)
      ];
      mqtt.binary_sensor = [{
        name = "Piec plomien aktywne";
        unique_id = "piec_plomien_aktywne";
        default_entity_id = "binary_sensor.piec_plomien_aktywne";
        state_topic = "ebusd/boiler/flame_active";
        value_template = "{{ value_json.onoff.value }}";
        payload_on = "on";
        payload_off = "off";
        device_class = "heat";
        inherit availability;
        availability_mode = "all";
        expire_after = 120;
      }];
      template = [
        (modeTemplates "co" "CO" "heating")
        (modeTemplates "cwu" "CWU" "heating hot water")
        {
          switch = [{
            name = "Piec ogrzewanie TA1";
            unique_id = "piec_ogrzewanie_ta1";
            optimistic = true;
            state = "{{ states('sensor.piec_pin6') == '1' }}";
            turn_on = [{ action = "mqtt.publish"; data = { topic = "eas/io.6"; payload = "1"; }; }];
            turn_off = [{ action = "mqtt.publish"; data = { topic = "eas/io.6"; payload = "0"; }; }];
          }];
        }
        {
          binary_sensor = [{
            name = "Piec dane aktualne";
            unique_id = "piec_dane_aktualne";
            default_entity_id = "binary_sensor.piec_dane_aktualne";
            device_class = "connectivity";
            state = "{{ has_value('sensor.piec_status') }}";
          }];
          sensor = [
            (coTemperature "zasilanie" "Piec CO zasilanie")
            (coTemperature "powrot" "Piec CO powrot")
            {
              name = "Piec tryb";
              unique_id = "piec_tryb";
              default_entity_id = "sensor.piec_tryb";
              availability = "{{ has_value('sensor.piec_status') }}";
              state = "{{ {'standby': '🟢 Gotowość', 'heating': '🟠 CO — kaloryfery', 'heating hot water': '🔵 CWU — woda w kranach', 'circulating': '🟡 Obieg pompy', 'comfort': '🟣 Komfort CWU', 'low_water_pressure': '🔴 Niskie ciśnienie', 'no_flame': '🔴 Brak płomienia'}.get(states('sensor.piec_status'), '⚪ ' ~ states('sensor.piec_status')) }}";
            }
            {
              name = "Piec CO Delta T";
              unique_id = "piec_co_delta_t";
              default_entity_id = "sensor.piec_co_delta_t";
              unit_of_measurement = "K";
              state_class = "measurement";
              availability = "{{ is_state('binary_sensor.piec_co_aktywne', 'on') and is_number(states('sensor.piec_zasilanie')) and is_number(states('sensor.piec_powrot')) }}";
              state = "{{ (states('sensor.piec_zasilanie') | float(0) - states('sensor.piec_powrot') | float(0)) | round(1) }}";
            }
          ];
        }
      ];
      sensor = modeStats "co" ++ modeStats "cwu" ++ [
        (historyStat "plomien" "czas dzisiaj" "time" "czas_dzisiaj" "{{ today_at('00:00') }}")
        (historyStat "plomien" "cykle dzisiaj" "count" "cykle_dzisiaj" "{{ today_at('00:00') }}")
      ]
        ++ temperatureStats "zasilanie" ++ temperatureStats "powrot"
        ++ temperatureStats "co_zasilanie" ++ temperatureStats "co_powrot" ++ temperatureStats "co_delta_t"
        ++ [
        (temperatureStat "zasilanie" "szczyt 24h" "datetime_value_max" 24)
        (temperatureStat "powrot" "szczyt 24h" "datetime_value_max" 24)
        (temperatureStat "zasilanie" "zakres 1h" "distance_absolute" 1)
        (temperatureStat "powrot" "zakres 1h" "distance_absolute" 1)
      ] ++ [{
        platform = "history_stats";
        name = "Piec dostepnosc dzisiaj";
        unique_id = "piec_dostepnosc_dzisiaj";
        entity_id = "binary_sensor.piec_dane_aktualne";
        state = "on";
        type = "ratio";
        start = "{{ today_at('00:00') }}";
        end = "{{ now() }}";
      }];
    };
  };
}
