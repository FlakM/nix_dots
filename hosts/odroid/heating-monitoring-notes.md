# Ariston Clas X 24 CF EU — dodatkowy monitoring

Stan badań: 2026-10-11. Kocioł niekondensacyjny, CWU przepływowe, bez
zewnętrznego zasobnika. Badanie źródeł uzupełnione ograniczonymi odczytami
na żywo; wyniki obserwacji zapisano poniżej.
Instrukcja potwierdza funkcje/menu, nie adresy BridgeNet. CSV v2.7 dotyczy
Genus One Hybrid Net, ysard — Mira/Serelia/Talia Green, kredow — m.in. Clas
Premium Evo; ich mapowania nie dowodzą obsługi na Clas X. [M], [W], [R], [K]

## Potwierdzone dla Clas X

Instrukcja producenta CLAS X CF, nr 420000470100, obejmuje model 24 CF EU
(s. 9). Opisuje czujnik przepływu CWU i wymiennik płytowy (s. 7/10) oraz:

| Menu | Dostępna diagnostyka według instrukcji |
| --- | --- |
| 800–803 | Cykle zaworu, czas/cykle pompy, czas pracy kotła; `n x10` / `h x10` |
| 806/807 | Osobne liczby zapłonów CO/CWU, `n x10` |
| 810–814 | Godziny CO/CWU, błędy zapłonu, zapłony ogółem, średnia długość żądania grzania |
| 820/823/824 | Modulacja 0–165 mA; pompa 0=OFF, 1=niska, 2=wysoka; zawór 0=CWU, 1=CO |
| 825/827/828 | Przepływ CWU w l/min, modulacja pompy w %, moc palnika (jednostka niepodana) |
| 830–833/835 | Temperatura zadana CO, zasilanie, powrót, temperatura CWU, temperatura zewnętrzna |
| 434/534/634 | Żądanie grzania strefy 1/2/3, OFF/ON |
| 860 | 10 ostatnich błędów z datą; to historia, nie bieżący alarm |

Źródło: [M], s. 24–25. Lista zawiera również pola wspólne dla innych
wariantów, np. wentylator i zasobnik; obecność pozycji nie gwarantuje
działającego pomiaru w tej instalacji. Model CF ma naturalny ciąg (s. 9).
COMFORT podgrzewa wymiennik wtórny; tryb czasowy trwa 30 minut po poborze,
tryb 2 działa stale (250, s. 23). Nie oznacza grzania zewnętrznego zbiornika. [M]

Odczyty wykonane w tej sesji:
`c428=mixed_instant`, `6829=24`, temperatury `6810`/`6910`, stany `c04b`
standby/CO/CWU i płomień `0e11`. Liczniki: `4bd1=1649`, `4cd1=272`,
`42d8=33151`, `42d2=3454`, `40d2=37008`. Nazwy rejestrów odpowiadają [W];
odczyt wartości nie potwierdza jeszcze jednostki/skali liczników.

## Kandydaci community — kolejność walidacji

Adresy poniżej to identyfikatory w kolejności bajtów na magistrali (kolumna
`ebus ID` u kredow). O ile nie wskazano inaczej: pojedynczy odczyt
`2000` do kotła `3c`; nie przenosić adresu Energy Managera `18` na tę instalację. [W], [Y], [K]

| Priorytet | Kandydat i źródło mapowania | Co można uzyskać / ograniczenie |
| --- | --- | --- |
| 1 | `0e11` płomień + `c04b` tryb [W], [Y] | Czas wykrytego płomienia i zbocza zapłonów z podziałem na tryb; porównać przyrost z `42d8`. To statystyka próbek, krótkie cykle mogą umknąć. Odczyty potwierdzone w sesji. |
| 2 | `0191` żądanie strefy 1; `6197` obliczona temperatura zadana CO [Y]; `0191` także [K] | Czas żądania, opóźnienie do płomienia, przerwy palnika podczas ciągłego żądania. Ysard opisuje broadcast kotła `37→fe/2010`; v2.7 filtruje żądanie do nadawcy `13` i odczytuje z `18` — to mapowanie hybrydy [W]. `1919` to aktywacja od regulatora, nie zamiennik `0191`. |
| 3 | `c000` bieżący poziom prędkości pompy [K], menu 823 [M] | OFF/niska/wysoka; czas pracy i wybieg pompy po zgaszeniu. Kredow potwierdza na Clas Premium Evo, nie Clas X; typ/rozmiar odpowiedzi wymagają sprawdzenia. `c228` z [W] opisuje ustawiony sposób pracy, nie bieżące ON/OFF. |
| 4 | `2002/0400` ostatni błąd; kolejne sloty `0401`–`0409` [W], [Y] | Historia serwisowa, porównać z menu 860. Zacząć od jednego slotu; nie traktować starego wpisu jako aktywnego alarmu. Pusty slot może dawać `00`/`invalid position`, nieustawiona data — błąd zakresu [R]. |
| 5 | `c028` ustawienie COMFORT 0/1/2 [W], [Y]; `c04b=24` praca COMFORT [W]; `d746` status komfortu [Y] | Oddzielić włączoną funkcję od rzeczywistego podgrzewania bez poboru. W pierwszej kolejności odczyt `c028` z `3c`; `d746` i stan 24 niepotwierdzone na Clas X. |
| 6 | `50d9` czas życia kotła, `44d2` cykle pompy [W]; `50d9` także [Y]; `46d1` oderwania płomienia [W] | Wolnozmienne diagnostyki; v2.7 używa `UIN`, dla `50d9` deklaruje minuty. Nie zakładać pełnej szerokości/skali/odporności na przepełnienie. `46d1` nie jest automatycznie licznikiem błędów zapłonu 812. |
| 7 | CWU: `6147` temperatura, `6847` przepływ/moc; `6510` „CWU measured temp?” [Y], [O], [W], [K] | Duża wartość użytkowa, ale konflikt lub hipoteza — wyłącznie walidacja z menu 833/825/828 przed wystawieniem temperatury, l/min, litrów czy kW. Szczegóły niżej. |

## Sprzeczne lub nieznane mapowania

- **CWU `6147`:** v2.7 nazywa broadcast `2010` temperaturą zadaną (`SIN/10`),
  ysard rzeczywistą (`U3N/10`), kredow „set temp” z pytajnikiem.
  To konflikt zarówno znaczenia, jak i długości pola: 2 kontra 3 bajty.
  `6126` jest lepszym kandydatem nastawy: ysard odczytuje z `3c` jako
  `dhw_target_temp`; v2.7 nazywa ją `dhw_comfort_temp` przy `18`. [W], [Y], [K], [D]
- **`6847`:** komw `dhw_flowmeter`, `UIN/10`, jednostka `L` (nie udowodnione
  l/min); v2.7 `flame_power_kw`, `UIN/10`; kredow „gas power ?”.
  Autor v2.7 obserwował wartość także podczas CO na Genus i później porównał
  ją z menu bieżącej mocy swojego kotła. Jest więc źródłowe uzasadnienie kW
  dla Genus, ale nie dowód dla Clas X ani pomiar zużycia gazu.
  Pozostawić wyłączone do porównania z menu 825 i 828. [O], [W], [K], [P]
- **Rzeczywista CWU:** kredow podaje `6510` jako pytanie i `6210` jako
  przypuszczalne 833 „zawsze 0”; nie są to potwierdzone czujniki Clas X.
  Menu 833 nie dowodzi obecności osobnej sondy na wypływie ani temperatury
  w kranie; schemat pokazuje sondy CO i przepływomierz CWU. [K], [M] s. 7/10/25
- **Skale liczników:** menu opisuje `h x10` / `n x10`, v2.7 dla `4bd1` używa
  `UIN` bez dzielnika, ysard `UIN/10`. Nie wiadomo, jak skala menu odnosi się
  do wartości rejestru; nie mnożyć/dzielić wszystkich liczników arbitralnie.
  `806`, `807`, `812`, `814` nie mają ustalonego mapowania w sprawdzonych
  źródłach. Zakomentowane `heat_request_avg_duration=42d2` w v2.7 koliduje
  z `hours_pump_on`; nie używać go jako 814. [M], [W], [Y]
- **Pompa/zawór/modulacja:** `c300` jest kandydatem % pompy [W], [K], ale
  wcześniejszy dekoder `UIN` zwrócił `invalid position`; nie oznacza to 0%.
  `0001` jako pozycja zaworu [K] konkuruje z `c012` [W]. `c404` w v2.7 to
  surowy `UCH` bez jednostki, u kredow bez opisu; menu 820 podaje mA,
  lecz nie łączy ich z tym adresem. Żadnego przeliczania na %, kW lub kWh. [M], [W], [K]
- **Alarm bieżący:** `2004` przenosi pojawienie i ustąpienie błędu; potrzeba
  kodu, flag aktywności/strefy i deduplikacji. Sam `energymgr/error` z v2.7
  dekoduje tylko kod. `_templates.csv` jest jawnie dla hybrydy Nimbus+Genus;
  nie traktować opisów jako sprawdzonych na Clas X. `ec` ysard wiąże z brakiem
  sondy zewnętrznej, v2.7 spekuluje o okresowych `ec/ee` jako keepalive;
  nie nadawać im automatycznie alarmu ani znaczenia „kocioł zdrowy”. [R], [W], [E]
- **Brak sond:** v2.7 dokumentuje surowe `0x7fff` dla `7310` jako brak/uszkodzenie
  sondy zewnętrznej i mapuje je na 0. Bez tego mapowania `SIN/10` daje 3276,7°C;
  właściwy wynik to niedostępność, nie 0°C. Dla `7647` i pokojowego `7118`
  sentinel trzeba potwierdzić osobno; sam suchy styk TA1 nie dostarcza pomiaru
  temperatury pokoju. Nie przenosić sentinela między polami. [W], [R], [D], [M] s. 12

## Ograniczona walidacja tylko do odczytu

1. Najpierw przeanalizować zapisane telegramy/broadcasty: nadawca, `PBSB`, ID,
   długość, surowe bajty. Sprawdzić offline granice pól `6147` i odpowiedź
   `c300`; `UCH` ma 1 bajt, `UIN`/`SIN` 2, `U3N` 3. [D]
2. Przy kolejnych obserwacjach: pojedyncze odczyty
   tylko znanych ID z tabeli, po jednym kandydacie, najwyżej kilka próbek
   na stan: gotowość, naturalny cykl CO, zwykły pobór CWU i wybieg pompy.
   Równolegle porównać wyłącznie wyświetlane menu 823/825/828/833/434.
   Zacząć od cache; świeży odczyt tylko gdy potrzebny. Nie skanować przestrzeni
   rejestrów, nie odtwarzać alarmów, nie resetować i niczego nie zapisywać. [R]
3. Liczniki porównać z menu 800/801/803/810/811/813 oraz z przyrostem podczas
   znanego okresu płomienia/pompy. Osobne zapłony 806/807 można na razie
   odnotować z panelu; bez adresów nie dodawać automatycznego odczytu. [M], [W], [Y]
4. Promować do monitoringu dopiero zgodność stanu, jednostki i skali;
   brak danych/sentinel/błąd dekodera oznaczają niedostępność. `860` sprawdzić
   jednym slotem, bez wywoływania usterki. Nieudowodnione mapowania zachować
   jako surową diagnostykę, bez statystyk fizycznych.

## Uzasadnienie wprowadzonych korekt

- `heating-monitoring.nix`: poprzedni sensor `piec_cwu_zadana` przypisywał
  pewne znaczenie spornemu `6147`. Zastąpiono go `piec_cwu_6147`, bez
  jednostki fizycznej, z etykietą niepotwierdzonego dekodera community.
  Nie uznano go za temperaturę rzeczywistą. [W], [Y], [K]
- Godzinowe jednostki liczników są prowizoryczne, także przy dopisku „CSV”.
  Zachowano surowe wartości bez `h`; fizyczne jednostki zależą od
  walidacji skali. Epizody `c04b` pozostają epizodami trybu; dopiero
  `0e11` pozwala oszacować czas płomienia. [M], [W], [Y]
- Usunięcie `6847` jako pewnego kW, ciśnienia `7547` oraz zerowania brakującej
  sondy `7310` jest uzasadnione. Wcześniejszy `c328=temp_probe` zgadza się
  z menu 247 (NTC), więc `7547=0` nie jest dowodem zerowego ciśnienia. [M], [W], [O], [P]

## Walidacja na żywo — 2026-10-11

- Pojedyncze zapytania `0191`, `6197`, `6126` i `c028` do `3c/2000`
  zwróciły `0100`; proponowane dekodery nie mają wymaganych bajtów danych.
  Nie wystawiono sensorów ani nie dodano pollingu tych zapytań.
- `6510` zwróciło `3276,7` z dekodera `SIN/10` (`0x7fff`). Wartość
  niefizyczna, odrzucona; nie jest temperaturą CWU.
- `c300` odpowiada na jednobajtowy `UCH` (wartość 0), podczas gdy wcześniejszy
  `UIN` nie pasował do długości. To potwierdza szerokość odpowiedzi,
  nie jednostkę procentową ani działający pomiar modulacji pompy.
- `c000` zwróciło 1 również w gotowości. Nie rozstrzyga to, czy opisuje
  bieżące obroty, prędkość zadaną czy wybieg; pozostaje kandydatem.
- Obserwacja 00:57:33–00:58:28: `standby`, płomień `off`, `c404=0`,
  `6847=0,0`, `c000=1`, `c300=0`. Zasilanie spadło 51,9→50,8°C,
  powrót 53,5→52,3°C. Pokazuje stygnięcie obiegu; nie waliduje mocy,
  przepływu CWU ani gazu. Powrót cieplejszy od zasilania w tym stanie
  nie jest samodzielnym dowodem usterki; Delta T CO jest liczone tylko
  podczas trybu ogrzewania.
- Poprawiono etykietę `6147` na niepotwierdzony rejestr bez jednostki
  fizycznej. Liczniki czasu kotła są dostępne jako surowe rejestry;
  czas CO/CWU i płomienia w panelu pochodzi z historii stanów HA.
- `ariston-clas-x-readonly.csv` zachowuje tylko trzy kandydackie odczyty
  (`c000`, `6847`, `c300`) bez automatycznego pollingu i discovery.
  Wadliwa, kolidująca definicja `c300/UIN` z v2.7 została pominięta.

## Czy można mierzyć rzeczywiste zużycie gazu?

**Werdykt: obecny potwierdzony zestaw czujników nie mierzy m³ ani energii
zużytego gazu.** Instrukcja i sprawdzone mapy [W], [O], [Y], [K] nie ustalają
dla Clas X ani skumulowanego licznika gazu/energii paliwa, ani mierzonego
chwilowego przepływu gazu. Liczniki godzin/zapłonów nie są gazomierzem;
przepływ w menu 825 dotyczy wody CWU. To brak potwierdzenia w źródłach,
nie dowód, że żaden taki rejestr nie istnieje. [M], s. 25

### Dane znamionowe, nie bieżący pomiar

W tabeli s. 29 „wydajność cieplna” Hi/Hs oznacza moc doprowadzaną w paliwie
(`P_input`), a „moc cieplna” — moc użyteczną (`P_output`); stosunek wartości
odpowiada podanym sprawnościom. Hi to wartość opałowa, Hs — ciepło spalania.
Dla **24 CF EU**, maks./min.: [M]

| Tryb | Wejście Hi, kW | Wejście Hs, kW | Wyjście użyteczne, kW |
| --- | --- | --- | --- |
| CO | 25,8 / 11,0 | 28,7 / 12,2 | 23,2 / 9,8 |
| CWU | 27,0 / 11,0 | 30,0 / 12,2 | 24,3 / 9,9 |

Tabela regulacji gazu s. 17 podaje poniższe strumienie przy 15°C i 1013 mbar.
Są to wartości znamionowe dla wskazanych obciążeń, nie odczyt przepływomierza: [M]

| Gaz | Maks. CWU | Maks. CO | Minimum | Jednostka |
| --- | --- | --- | --- | --- |
| G20 | 2,86 | 2,73 | 1,16 | m³/h |
| G31 | 2,10 | 2,00 | 0,85 | kg/h |
| G30 | brak danych | brak danych | brak danych | — |

Ta wersja instrukcji wymienia G20/G2.350/G27/G31, bez G30; nie przenosić
danych butanu z innego modelu ani kg/h LPG na m³/h gazu ziemnego. Wskaźnik
Wobbego z tej tabeli nie jest współczynnikiem kWh/m³. Nazwa „24 kW” i
`nominal_power=24` nie oznaczają stałego poboru paliwa. **24 kW × czas pracy
nie jest zmierzonym zużyciem gazu**, również przy czasie samego płomienia. [M], [W]

### Cztery różne metody

1. **Pomiar gazomierzem:** odczyt liczydła lub czujnik impulsów zgodny z jego
   modelem daje rzeczywistą zmierzoną objętość; przelicznik m³/impuls ustalić
   z dokumentacji konkretnego gazomierza. Licznik wspólny obejmuje także inne
   odbiorniki gazu. To najlepsza ścieżka pomiarowa według [HA-gaz].
2. **Całkowanie mierzonego przepływu:** gdyby potwierdzono rzeczywisty
   `q_gas(t)` w m³/h, `V = ∫q_gas(t) dt` (czas w godzinach) daje objętość.
   Wymaga potwierdzonego sensora, jednostki, warunków odniesienia objętości,
   odpowiedniej częstotliwości i obsługi luk; obecnie takiego pola nie mamy.
3. **Model z modulacji/prądu zaworu lub czasu płomienia:** tylko oszacowanie,
   wymagające charakterystyki i kalibracji względem gazomierza. Nie zakładać
   liniowej zależności `c404` od strumienia; jednostka nadal niepotwierdzona,
   a menu 820 podaje mA, nie m³/h. [M], [W], [K]
4. **Całkowanie mocy:** `∫P(t) dt` daje kWh tej mocy, nie automatycznie energię
   gazu. Wyłącznie dla zweryfikowanej bieżącej **mocy wejściowej paliwa**:
   `q_gas [m³/h] = P_input [kW] / H_gas [kWh/m³]`.
   Podstawa Hi/Hs i warunki objętości muszą się zgadzać; użyć właściwego
   współczynnika dla dostarczanego gazu. Jeśli pole oznacza moc wyjściową,
   potrzeba jeszcze rzeczywistej sprawności (`P_input = P_output / η`);
   sprawność katalogowa nie gwarantuje przeliczenia w każdej chwili. To
   warunkowy bilans energii, nie potwierdzone mapowanie `6847`. [M], [P]

W [issue #24](https://github.com/wrongisthenewright/ebusd-configuration-ariston-bridgenet/issues/24)
autor obserwował `6847` podczas CO na Genus; w [P] nazwał je bieżącą mocą
wyjściową i proponował przybliżone dzielenie przez 11,06. Nie ustalił tym
pomiaru przepływu gazu ani `P_input` na Clas X. W [późniejszym komentarzu](https://github.com/wrongisthenewright/ebusd-configuration-ariston-bridgenet/issues/20#issuecomment-2664214073)
zapowiadał dopiero porównanie z gazomierzem, a [użytkownik v2.6](https://github.com/wrongisthenewright/ebusd-configuration-ariston-bridgenet/issues/20#issuecomment-2679784729)
zgłaszał moc chwilową zamiast energii całkowitej. To nie dowodzi licznika
zużycia na Clas X; nie ma podstaw do deklarowania dokładności oszacowania.

**Najbliższa walidacja:** ustalić model gazomierza, możliwość odczytu i rodzaj
gazu z tabliczki/dokumentów; zacząć od porównania przyrostu jego liczydła
z zapisanym czasem płomienia. Dopiero później kilka odczytów `6847` podczas
naturalnych cykli zestawić z menu 825/828 i gazomierzem, bez skanowania,
zapisów ani trybu testowego. Zgodność z menu mocy nie rozstrzyga jeszcze
wejścia/wyjścia ani sposobu wyznaczania wartości. [M], [W], [P], [HA-gaz]

Przy małym zapotrzebowaniu minimum mocy i taktowanie, rozruch/powolny zapłon
oraz COMFORT komplikują model czasu/modulacji. Próbkowanie może pominąć
krótkie zapłony/pobory; podgrzewanie wstępne zużywa gaz bez otwartego kranu,
a wybieg pompy nie oznacza spalania. Podział gazu CO/CWU/COMFORT wymaga
zsynchronizowanych próbek i osobnej kategorii stanów przejściowych/braku
danych; temperatura i przepływ wody mierzą inny bilans niż paliwo. [M], s. 16/23/29; [W]

[HA-gaz]: https://www.home-assistant.io/docs/energy/gas/

## Źródła pierwotne

[M]: https://www.kamody.cz/soubory/relatedfile/PL_ARISTON_CLAS_X_24_CF_3301313_3301314_MANUAL.pdf
[W]: https://github.com/wrongisthenewright/ebusd-configuration-ariston-bridgenet/blob/v2.7/ariston.csv
[E]: https://github.com/wrongisthenewright/ebusd-configuration-ariston-bridgenet/blob/v2.7/_templates.csv
[O]: https://github.com/komw/ariston-bus-bridgenet-ebusd/blob/master/configuration/ariston.csv
[Y]: https://github.com/ysard/ebusd_configuration_chaffoteaux_bridgenet/blob/master/mira_c_green.csv
[K]: https://github.com/kredow/ariston-ebus-prococol/blob/main/ariston_register_map.csv
[P]: https://github.com/wrongisthenewright/ebusd-configuration-ariston-bridgenet/issues/20#issuecomment-2541920802
[D]: https://github.com/john30/ebusd/wiki/4.3.-Builtin-data-types
[R]: https://github.com/ysard/ebusd_configuration_chaffoteaux_bridgenet/blob/master/README.md

Reverse engineering protokołu, alarmów i pustych slotów: [ysard README](https://github.com/ysard/ebusd_configuration_chaffoteaux_bridgenet#protocol-for-the-errors).
Instrukcję odczytano z istniejącego `/tmp/opencode/ariston-clas-x-manual.txt`;
numery stron odnoszą się do druku. Źródła `master/main` sprawdzone na datę badań.
