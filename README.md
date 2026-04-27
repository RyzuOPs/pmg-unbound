# PMG Unbound

**Menadżer lokalnego rekurencyjnego DNS resolvera dla Proxmox Mail Gateway**

Skrypt instaluje i zarządza serwerem DNS Unbound na PMG, aby uniknąć limitów zapytań podczas sprawdzania adresów IP na listach RBL (Realtime Blackhole Lists).

## 🎯 Problem

Proxmox Mail Gateway sprawdza każdy przychodzący email na wielu listach RBL (np. Spamhaus, SORBS, SpamCop). Bezpośrednie zapytania do publicznych serwerów DNS szybko wyczerpują limity rate-limit, co powoduje:
- Opóźnienia w przetwarzaniu poczty
- Błędy DNS timeout
- Potencjalne blokady IP serwera

## ✅ Rozwiązanie

Unbound jako lokalny rekurencyjny resolver:
- **Bezpośrednie zapytania** do autoritatywnych serwerów DNS (bez pośredników)
- **Brak limitów** zapytań RBL
- **Inteligentny cache** - optymalizowany dla RBL
- **Wysoka wydajność** - szybsze odpowiedzi DNS

## 📦 Instalacja

### 1. Pobierz skrypt
```bash
wget https://raw.githubusercontent.com/RyzuOPs/pmg-unbound/main/pmg-unbound.sh
chmod +x pmg-unbound.sh
```

### 2. Zainstaluj Unbound
```bash
./pmg-unbound.sh install
```

Podczas instalacji zostaniesz zapytany czy dodać miesięczny cron do aktualizacji root hints (zalecane: TAK).

### 3. Skonfiguruj DNS w PMG

⚠️ **WAŻNE:** Po instalacji musisz ręcznie zmienić DNS w GUI:

1. Zaloguj się do interfejsu webowego PMG
2. Przejdź do: **System → Network Configuration**
3. Wybierz interfejs sieciowy (np. vmbr0)
4. Kliknij **Edit**
5. Zmień **DNS Server 1** na: `127.0.0.1`
6. Kliknij **OK** i **Apply Configuration**

## 🚀 Użycie

### Podstawowe komendy
```bash
# Instalacja
./pmg-unbound.sh install

# Status serwisu
./pmg-unbound.sh status

# Statystyki (cache hits, zapytania)
./pmg-unbound.sh stats

# Test DNS i RBL
./pmg-unbound.sh test

# Deinstalacja
./pmg-unbound.sh uninstall
```

### Zaawansowane
```bash
# Włącz logowanie zapytań (debug)
./pmg-unbound.sh debug on

# Wyłącz logowanie zapytań
./pmg-unbound.sh debug off

# Aktualizuj root DNS hints ręcznie
./pmg-unbound.sh update-hints
```

## 📋 Typowy workflow

### Po pierwszej instalacji:
```bash
# 1. Zainstaluj i skonfiguruj
./pmg-unbound.sh install
# Odpowiedz 'Y' na pytanie o cron

# 2. Przetestuj działanie
./pmg-unbound.sh test

# 3. Sprawdź status
./pmg-unbound.sh status

# 4. Zmień DNS w PMG GUI na 127.0.0.1 (System → Network Configuration)
```

### Codzienne użycie:
```bash
# Sprawdź czy wszystko działa
./pmg-unbound.sh status

# Zobacz statystyki cache (jak dużo oszczędzasz zapytań)
./pmg-unbound.sh stats

# Jeśli masz problemy, włącz debug
./pmg-unbound.sh debug on
tail -f /var/log/unbound/unbound.log
# ... diagnoza ...
./pmg-unbound.sh debug off
```

### Debugowanie problemów:
```bash
# 1. Sprawdź status serwisu
./pmg-unbound.sh status

# 2. Testuj rezolwowanie DNS
./pmg-unbound.sh test

# 3. Włącz szczegółowe logi
./pmg-unbound.sh debug on

# 4. Zobacz logi w czasie rzeczywistym
tail -f /var/log/unbound/unbound.log

# 5. Sprawdź logi systemowe
journalctl -u unbound -n 50

# 6. Po naprawie wyłącz debug
./pmg-unbound.sh debug off
```

### Konserwacja:
```bash
# Miesięczna aktualizacja root hints (lub automatycznie przez cron)
./pmg-unbound.sh update-hints

# Sprawdzenie efektywności cache
./pmg-unbound.sh stats | grep cache

# Restart serwisu (jeśli potrzebny)
systemctl restart unbound
```

## ⚙️ Konfiguracja

### Optymalizacje dla RBL

Skrypt automatycznie konfiguruje:

**TTL Cache:**
- `cache-min-ttl: 300` (5 min) - odpowiedzi pozytywne (IP na blackliście)
- `cache-min-negative-ttl: 3600` (60 min) - odpowiedzi negatywne (IP czyste)
- `cache-max-ttl: 86400` (24h) - maksymalny TTL

**Wydajność:**
- `msg-cache-size: 50m` - cache wiadomości
- `rrset-cache-size: 100m` - cache rekordów
- `neg-cache-size: 4m` - cache negatywnych odpowiedzi
- `num-threads: 2` - wielowątkowość
- `so-reuseport: yes` - lepsza dystrybucja zapytań
- `outgoing-range: 8192` - więcej portów dla zapytań wychodzących
- `infra-cache-numhosts: 10000` - większy cache infrastruktury

**Bezpieczeństwo:**
- `hide-identity: yes`
- `hide-version: yes`
- `harden-glue: yes`
- `harden-dnssec-stripped: yes`

### Logowanie

Domyślnie logowane są tylko błędy (`/var/log/unbound/unbound.log`).

Włącz pełne logowanie zapytań dla debugowania:
```bash
./pmg-unbound.sh debug on
tail -f /var/log/unbound/unbound.log
```

## 📊 Statystyki

Sprawdź efektywność cache:

```bash
./pmg-unbound.sh stats
```

Przykładowy wynik:
```
total.num.queries=123456
total.cache.hits=98765
total.recursion.time.avg=0.123456
```

Cache hit ratio > 80% = świetna optymalizacja! 🎉

## 🔧 Utrzymanie

### Automatyczna aktualizacja root hints

Jeśli podczas instalacji włączyłeś cron, root hints będą aktualizowane automatycznie co miesiąc.

Ręczna aktualizacja:
```bash
./pmg-unbound.sh update-hints
```

### Monitoring

Sprawdź czy Unbound działa poprawnie:
```bash
systemctl status unbound
./pmg-unbound.sh test
```

## 🐛 Troubleshooting

### Unbound nie startuje
```bash
# Sprawdź logi
journalctl -u unbound -n 50

# Waliduj konfigurację
unbound-checkconf
```

### DNS nie działa po zmianie w GUI
```bash
# Sprawdź czy DNS wskazuje na localhost
cat /etc/resolv.conf

# Zrestartuj unbound i PMG
systemctl restart unbound
systemctl restart pmgproxy pmgdaemon
```

### Niski cache hit ratio
```bash
# Włącz debug i obserwuj zapytania
./pmg-unbound.sh debug on
tail -f /var/log/unbound/unbound.log

# Sprawdź czy PMG używa 127.0.0.1
dig google.com @127.0.0.1
```

## 📋 Wymagania

- **System:** Proxmox Mail Gateway (bazujący na Debianie)
- **Uprawnienia:** root
- **Pakiety:** apt, wget, systemd (standardowo dostępne w PMG)

## 🔒 Bezpieczeństwo

- Unbound nasłuchuje **tylko** na `127.0.0.1` (localhost)
- Brak dostępu z zewnątrz
- Rekurencyjne rozwiązywanie nazw bezpośrednio do autoritatywnych serwerów

## 📝 Licencja

MIT License - użyj, modyfikuj, udostępniaj swobodnie.

## 🤝 Wsparcie

Problemy? Sugestie? Otwórz Issue na GitHubie!

## 🌟 Autor

Skrypt stworzony dla optymalizacji Proxmox Mail Gateway.

---

**Podobał się projekt? Daj gwiazdkę ⭐ na GitHubie!**
