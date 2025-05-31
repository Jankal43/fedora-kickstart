
# Sprawozdanie: Automatyzacja i Zdalne Wykonywanie Poleceń za Pomocą Ansible

## Wprowadzenie

Celem niniejszego ćwiczenia jest zapoznanie się z narzędziem Ansible, służącym do automatyzacji zarządzania konfiguracją oraz zdalnego wykonywania zadań na wielu systemach jednocześnie. W ramach sprawozdania zostanie przedstawiony proces instalacji Ansible na maszynie kontrolnej, konfiguracji maszyn zarządzanych (endpointów), tworzenia inwentarza systemów, wykonywania zadań ad-hoc oraz implementacji złożonych operacji za pomocą playbooków i ról Ansible. Ćwiczenie obejmuje również zarządzanie artefaktem (obrazem Docker) z poprzednich zajęć przy użyciu Ansible.

## Część 1: Instalacja Zarządcy Ansible i Przygotowanie Środowiska

Pierwszym krokiem było przygotowanie odpowiedniego środowiska pracy, składającego się z maszyny kontrolnej (orchestratora) oraz maszyny zarządzanej (endpointu).

### 1.1. Przygotowanie Maszyny Zarządzanej (`ansible-target`)

Zgodnie z poleceniem, utworzono nową maszynę wirtualną, która będzie pełniła rolę endpointu zarządzanego przez Ansible.
*   **System Operacyjny:** Fedora (wersja zgodna z maszyną orchestratora).
*   **Wymagane oprogramowanie:** Zapewniono obecność programu `tar` oraz serwera OpenSSH (`sshd`) do komunikacji.
*   **Hostname:** Maszynie nadano hostname `ansible-target` podczas procesu instalacji.
*   **Użytkownik:** Utworzono dedykowanego użytkownika `ansible` na tej maszynie, który będzie wykorzystywany przez Ansible do logowania i wykonywania zadań. Użytkownik ten posiada uprawnienia do wykonywania poleceń z `sudo` bez potrzeby podawania hasła (konfiguracja w pliku `/etc/sudoers.d/ansible` z wpisem `ansible ALL=(ALL) NOPASSWD:ALL`).


### 1.2. Instalacja Ansible na Maszynie Kontrolnej (`ansible-orchestrator`)

Na głównej maszynie wirtualnej, pełniącej rolę orchestratora, zainstalowano oprogramowanie Ansible. Wykorzystano do tego menedżer pakietów `dnf` dostępny w systemie Fedora.

```bash
sudo dnf install ansible -y
```

Po instalacji sprawdzono wersję Ansible, aby potwierdzić poprawność instalacji:

```bash
ansible --version
```
![screen](screenshot/s1.png)

### 1.3. Konfiguracja Użytkownika `ansible` i Wymiana Kluczy SSH

Aby umożliwić Ansible bezhasłowe logowanie do maszyny zarządzanej, konieczne było skonfigurowanie użytkownika `ansible` na maszynie kontrolnej oraz wymiana kluczy SSH.

![screen](screenshot/s2.png)

Na maszynie `ansible-orchestrator` utworzono użytkownika `ansible`. Następnie, działając jako ten użytkownik (lub z jego uprawnieniami), wygenerowano parę kluczy SSH (publiczny i prywatny):

Następnie klucz publiczny użytkownika `ansible` z maszyny `ansible-orchestrator` został skopiowany do pliku `~/.ssh/authorized_keys` użytkownika `ansible` na maszynie `ansible-target`. Użyto do tego polecenia `ssh-copy-id`:

```bash
ssh-copy-id ansible@ansible-target
```
Ten krok wymaga jednorazowego podania hasła użytkownika `ansible` na maszynie `ansible-target`.

Po pomyślnym skopiowaniu klucza, przetestowano połączenie SSH z maszyny `ansible-orchestrator` do `ansible-target` jako użytkownik `ansible`. Połączenie powinno zostać nawiązane bez pytania o hasło.

```bash
ssh ansible@ansible-target
```

![screen](screenshot/s3.png)

Ta konfiguracja jest kluczowa dla działania Ansible, które polega na połączeniach SSH do zarządzania hostami.




























## Część 2: Inwentaryzacja Systemów

Po przygotowaniu maszyn i zapewnieniu podstawowej komunikacji SSH, kolejnym krokiem jest zdefiniowanie dla Ansible, którymi maszynami ma zarządzać. Służy do tego plik inwentarza.

### 2.1. Ustalenie Nazw Hostów i Konfiguracja Rozpoznawania Nazw

Aby ułatwić identyfikację maszyn, nadano im przewidywalne nazwy. Maszyna zarządzana otrzymała hostname `ansible-target` już podczas instalacji. Głównej maszynie wirtualnej (orchestratorowi) nadano hostname `ansible-orchestrator` za pomocą polecenia `hostnamectl`:

Na maszynie `ansible-orchestrator`:
```bash
sudo hostnamectl set-hostname ansible-orchestrator
```
![screen](screenshot/s3.png)

Następnie, aby umożliwić komunikację między maszynami z użyciem ich nazw (a nie tylko adresów IP), zaktualizowano pliki `/etc/hosts` na obu maszynach.

Na maszynie `ansible-orchestrator` dodano wpis dla `ansible-target`:
```bash
sudo nano /etc/hosts
```

Analogicznie, na maszynie `ansible-target` dodano wpis dla `ansible-orchestrator`:
```bash
sudo nano /etc/hosts
```

![screen](screenshot/s5.png)



### 2.2. Weryfikacja Łączności

Po konfiguracji nazw, zweryfikowano podstawową łączność sieciową między maszynami za pomocą polecenia `ping`, używając nowo zdefiniowanych nazw hostów.

Z maszyny `ansible-orchestrator` do `ansible-target`:
```bash
ping ansible-target
```

![screen](screenshot/s6.png)

Z maszyny `ansible-target` do `ansible-orchestrator`:
```bash
ping ansible-orchestrator
```
![screen](screenshot/s7.png)

Pomyślne wyniki testów `ping` potwierdziły, że obie maszyny są widoczne w sieci i poprawnie rozpoznają swoje nazwy.

### 2.3. Stworzenie Pliku Inwentarza Ansible

Plik inwentarza (`inventory.ini`) jest sercem konfiguracji Ansible, definiującym zarządzane hosty i ich grupy. Utworzono plik `inventory.ini` w katalogu roboczym na maszynie `ansible-orchestrator`.

Początkowa zawartość pliku `inventory.ini`:
```ini
[orchestrators]
localhost ansible_connection=local

[endpoints]
ansible-target ansible_user=ansible
```
Powyższy plik definiuje dwie grupy: `orchestrators` (zawierającą maszynę kontrolną) oraz `endpoints` (zawierającą maszynę zarządzaną).

![screen](screenshot/s10.png)

Następnie przetestowano konfigurację inwentarza za pomocą modułu `ping` Ansible, który sprawdza, czy Ansible jest w stanie połączyć się z hostami i wykonać na nich prosty kod Pythonowy.

```bash
ansible all -i inventory.ini -m ping
```
![screen](screenshot/s9.png)


   
Wynik "SUCCESS" dla obu hostów (`localhost` i `ansible-target`) potwierdza, że Ansible jest gotowy do zarządzania zdefiniowanymi systemami.






























## Część 3: Zdalne Wywoływanie Procedur za Pomocą Playbooka

Playbooki Ansible pozwalają na definiowanie złożonych sekwencji zadań do wykonania na zarządzanych hostach. Zgodnie z zadaniem, utworzono playbook `playbook.yml` realizujący serię operacji na maszynie `ansible-target`.

### 3.1. Tworzenie Playbooka `playbook.yml`

Plik `playbook.yml` został utworzony na maszynie `ansible-orchestrator` i zawiera następujące zadania:

```yaml
---
- name: Operacje zdalne na maszynach końcowych
  hosts: endpoints
  become: true
  tasks:
    - name: Ping - sprawdzenie łączności
      ansible.builtin.ping:

    - name: Skopiuj plik inwentaryzacji na maszynę docelową
      ansible.builtin.copy:
        src: inventory.ini
        dest: /home/ansible/inventory.ini
        owner: ansible
        mode: '0644'

    - name: Ping - ponownie sprawdź łączność
      ansible.builtin.ping:

    - name: Aktualizuj pakiety (dnf)
      ansible.builtin.dnf:
        name: "*"
        state: latest
        update_cache: yes

    - name: Restart usługi sshd
      ansible.builtin.service:
        name: sshd
        state: restarted

    - name: Restart usługi rngd (jeśli istnieje)
      ansible.builtin.service:
        name: rngd
        state: restarted
      ignore_errors: yes
```

![screen](screenshot/s11.png)

**Uzasadnienie struktury playbooka:**
*   `name: Operacje zdalne na maszynach końcowych`: Opisowa nazwa dla całego playbooka.
*   `hosts: endpoints`: Określa, że zadania z tego "play-a" będą wykonywane na hostach zdefiniowanych w grupie `endpoints` w pliku `inventory.ini`.
*   `become: true`: Wskazuje, że zadania w tym play-u powinny być wykonywane z podniesionymi uprawnieniami (równoważne `sudo`). Jest to konieczne dla zadań takich jak aktualizacja pakietów czy restart usług.
*   `tasks:`: Lista zadań do wykonania.
    *   **Ping - sprawdzenie łączności**: Pierwsze zadanie wykorzystuje moduł `ansible.builtin.ping` do weryfikacji podstawowej łączności z hostem przed wykonaniem dalszych operacji.
    *   **Skopiuj plik inwentaryzacji**: Moduł `ansible.builtin.copy` kopiuje plik `inventory.ini` z maszyny orchestratora do katalogu domowego użytkownika `ansible` na maszynie docelowej (`ansible-target`). Ustawiono właściciela (`owner`) i uprawnienia (`mode`) dla skopiowanego pliku.
    *   **Ping - ponownie sprawdź łączność**: Kolejne wywołanie modułu `ping`. W zadaniu polecono "ponów operację, porównaj różnice w wyjściu". Pierwsze wykonanie zadania kopiowania pliku powinno zwrócić `changed: true`. Drugie uruchomienie tego samego playbooka (bez zmian w pliku źródłowym `inventory.ini`) powinno dla tego zadania zwrócić `changed: false` (lub `ok`), demonstrując idempotentność Ansible. W tym konkretnym playbooku mamy jednak dwa osobne zadania ping, a nie ponowne wykonanie kopiowania.
    *   **Aktualizuj pakiety (dnf)**: Moduł `ansible.builtin.dnf` służy do zarządzania pakietami w systemach bazujących na RPM (jak Fedora). `name: "*"` i `state: latest` oznaczają aktualizację wszystkich zainstalowanych pakietów do najnowszych dostępnych wersji. `update_cache: yes` zapewnia odświeżenie lokalnej pamięci podręcznej metadanych pakietów przed próbą aktualizacji.
    *   **Restart usługi sshd**: Moduł `ansible.builtin.service` zarządza usługami systemowymi. Tutaj restartuje usługę `sshd`.
    *   **Restart usługi rngd (jeśli istnieje)**: Próba restartu usługi `rng-tools` (`rngd`), która jest często używana do generowania entropii. Dodano `ignore_errors: yes`, ponieważ usługa `rngd` może nie być zainstalowana/aktywna na wszystkich systemach (szczególnie na minimalnych instalacjach), a jej brak nie powinien przerywać wykonania całego playbooka.

### 3.2. Uruchomienie Playbooka

Playbook został uruchomiony z maszyny `ansible-orchestrator` za pomocą polecenia `ansible-playbook`:

```bash
ansible-playbook -i inventory.ini playbook.yml
```

![screen](screenshot/s12.png)

**Analiza wyniku wykonania**
*   **TASK [Gathering Facts]**: Zawsze wykonywane na początku (chyba że wyłączone), zbiera informacje o systemie docelowym. Stan: `ok`.
*   **TASK [Ping - sprawdzenie łączności]**: Pomyślnie. Stan: `ok`.
*   **TASK [Skopiuj plik inwentaryzacji na maszynę docelową]**: Plik został skopiowany. Stan: `changed`. Oznacza to, że stan systemu docelowego uległ zmianie (plik został utworzony lub zaktualizowany).
*   **TASK [Ping - ponowne sprawdź łączność]**: Pomyślnie. Stan: `ok`.
*   **TASK [Aktualizuj pakiety (dnf)]**: Pakiety zostały zaktualizowane. Stan: `changed`.
*   **TASK [Restart usługi sshd]**: Usługa `sshd` została zrestartowana. Stan: `changed`.
*   **TASK [Restart usługi rngd (jeśli istnieje)]**: Zadanie zakończyło się błędem (`fatal`), ponieważ usługa `rngd` nie została znaleziona na maszynie `ansible-target`. Jednak dzięki `ignore_errors: yes`, błąd ten został zignorowany (`ignored=1` w podsumowaniu `PLAY RECAP`), a playbook kontynuował swoje działanie.

W podsumowaniu `PLAY RECAP` dla `ansible-target` widzimy: `ok=7`, `changed=3`, `unreachable=0`, `failed=0`, `skipped=0`, `rescued=0`, `ignored=1`. Oznacza to, że 3 zadania dokonały zmian w systemie, a jedno zadanie, mimo błędu, zostało zignorowane i nie przerwało całości.

### 3.3. Weryfikacja Działania i Idempotentność

Zgodnie z poleceniem, aby zaobserwować idempotentność, można by ponownie uruchomić ten sam playbook:
```bash
ansible-playbook -i inventory.ini playbook.yml
```
Przy drugim uruchomieniu (zakładając, że plik `inventory.ini` na orchestratorze nie uległ zmianie i pakiety są już aktualne) oczekiwalibyśmy, że zadania "Skopiuj plik inwentaryzacji" oraz "Aktualizuj pakiety (dnf)" zgłoszą status `ok` (zamiast `changed`), ponieważ Ansible wykryje, że pożądany stan jest już osiągnięty. Restart usług (jak `sshd`) zazwyczaj zawsze będzie raportowany jako `changed` przez moduł `service` ze stanem `restarted`, chyba że użyto by bardziej zaawansowanej logiki z handlerami i warunkami.

### 3.4. Operacje Względem Maszyny z Problemami

Zadanie wspomina o "przeprowadzeniu operacji względem maszyny z wyłączonym serwerem SSH, odpiętą kartą sieciową".
Gdyby serwer SSH na `ansible-target` był wyłączony lub maszyna byłaby niedostępna sieciowo, Ansible podczas próby wykonania playbooka zgłosiłby błąd `unreachable` dla tej maszyny już na etapie "Gathering Facts" lub przy pierwszym zadaniu wymagającym połączenia.

Przykład komunikatu błędu dla hosta nieosiągalnego:
```
fatal: [ansible-target]: UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh: ssh: connect to host ansible-target port 22: No route to host", "unreachable": true}
```
Playbook nie kontynuowałby dalszych zadań dla takiego hosta.

---
Teraz przejdziemy do **Części 4: Zarządzanie Stworzonym Artefaktem**.
Zakładam, że artefaktem z poprzednich zajęć był obraz Docker (`mdoapp-deploy:latest`), który był zapisywany jako plik `.tar`. Będziemy potrzebowali tego pliku `.tar` na maszynie `ansible-orchestrator`, aby go przesłać i załadować na `ansible-target`.

Potrzebuję informacji:
1.  Czy masz plik `.tar` z obrazem Docker z poprzedniego zadania dostępny na `ansible-orchestrator`? Jeśli tak, podaj jego nazwę (np. `mdoapp-deploy-image-1.tar`).
2.  Potrzebne będą screeny:
    *   Zawartość nowego playbooka (`manage_artifact.yml` lub podobnie).
    *   Wynik uruchomienia tego playbooka.
    *   Screen weryfikujący, że Docker został zainstalowany na `ansible-target` (np. `ansible ansible-target -m shell -a "docker --version" --become`).
    *   Screen pokazujący, że obraz został załadowany na `ansible-target` (np. `ansible ansible-target -m shell -a "docker images"`).
    *   Screen pokazujący uruchomiony kontener (np. `ansible ansible-target -m shell -a "docker ps"`).
    *   Screen z `curl` do aplikacji działającej w kontenerze na `ansible-target`.
    *   Screen pokazujący zatrzymanie i usunięcie kontenera.

Daj znać, jakie masz materiały, a ja przygotuję odpowiednią sekcję.

