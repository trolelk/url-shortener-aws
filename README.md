# URL Shortener

Skracarka URL-i z asynchronicznym pobieraniem metadanych docelowej strony (tytuł, opis). Zbudowana na AWS, infrastruktura zarządzana w całości przez Terraform. CI/CD przez GitHub Actions z uwierzytelnianiem przez OIDC.

---

## Funkcjonalność

- Skracanie URL-i z deterministycznym kodem (hash)
- Przekierowanie (HTTP 302) z krótkiego linku na oryginalny
- Zliczanie wejść dla każdego skrótu
- Asynchroniczne pobieranie metadanych strony (`<title>`, `<meta description>`) w tle, bez blokowania odpowiedzi API
- Dokumentacja interaktywna (Swagger) pod `/docs`

---

## Architektura

```
                POST /shorten
                      |
                      v
          +-----------------------+
          |   ECS Fargate         |
          |   (FastAPI)           |---------> DynamoDB (urls)
          +-----------------------+           zapis skrótu + licznik
                      |
                      | zapis pliku JSON {url, code}
                      v
                 +---------+
                 |   S3    |
                 +---------+
                      |  (trigger: ObjectCreated)
                      v
            +--------------------+
            |   Lambda #1        |--------> DynamoDB (files)
            |   file_processor   |          status = pending
            +--------------------+
                      |
                      | send message
                      v
                 +---------+
                 |   SQS   |
                 +---------+
                      |  (trigger)
                      v
            +--------------------+
            |   Lambda #2        |  pobiera HTML strony,
            |   url_worker       |  wyciąga title / description
            +--------------------+
                      |
                      v
              DynamoDB (files)
              status = processed + metadane
```

Ruch z zewnątrz wchodzi przez **API Gateway** (stały adres, HTTPS) - > **ALB** - > zadania **ECS** w prywatnej podsieci. Aplikacja uzyskuje dostęp do DynamoDB i S3 przez rolę IAM przypisaną do zadania ECS - bez kluczy dostępowych w kodzie czy zmiennych środowiskowych.

Skrócenie URL-a poza zapisem do DynamoDB wrzuca też plik JSON do S3, co uruchamia łańcuch zdarzeń (event-driven): S3 wyzwala Lambdę #1, ta zapisuje rekord i publikuje wiadomość do SQS, SQS wyzwala Lambdę #2, która pobiera metadane strony i aktualizuje rekord.

---

## Stack

| Obszar           | Technologia                                        |
|------------------|----------------------------------------------------|
| Aplikacja        | Python, FastAPI                                    |
| Konteneryzacja   | Docker, ECS Fargate, ECR                          |
| Serverless       | AWS Lambda (x2)                                    |
| Kolejkowanie     | SQS                                               |
| Dane             | DynamoDB (`urls`, `files`)                        |
| Storage / trigger| S3                                               |
| Wejście / routing| API Gateway (HTTP API), Application Load Balancer  |
| Sieć             | VPC, public + private subnety, IGW, NAT Gateway    |
| IaC              | Terraform                                          |
| CI/CD            | GitHub Actions + OIDC      |

---

## API

| Metoda | Ścieżka         | Opis                                             |
|--------|-----------------|--------------------------------------------------|
| GET    | `/health`       | Health check (wykorzystywany przez ALB)          |
| POST   | `/shorten`      | Skraca URL; zwraca kod i krótki link             |
| GET    | `/r/{code}`     | Przekierowanie 302 na oryginalny URL + zliczenie |
| GET    | `/stats/{code}` | Statystyki pojedynczego skrótu                   |
| GET    | `/stats`        | Lista wszystkich skrótów                         |

### Przykład

```bash
curl -X POST https://<api-gateway-url>/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'
```

```json
{ "code": "a1b2c3d", "short_url": "/r/a1b2c3d" }
```

---

## Generowanie kodu skrótu

Kod skrótu powstaje jako pierwsze 7 znaków hasha MD5 z oryginalnego URL-a, nie z inkrementowanego licznika w bazie. To świadomy wybór pod kątem prostoty: hash jest deterministyczny i bezstanowy, nie wymaga osobnego mechanizmu generowania unikalnych ID (sequence, autoincrement) ani synchronizacji między instancjami aplikacji. Kosztem jest teoretyczna możliwość kolizji przy bardzo dużej liczbie URL-i oraz to, że kod jest przewidywalny (ten sam URL zawsze daje ten sam kod) - w produkcyjnym systemie zamieniłbym to na losowy, nieprzewidywalny identyfikator z dedykowanym mechanizmem unikalności.

---

## IaC

Terraform jest rozdzielony na dwie części:

**`bootstrap/`** - uruchamiany ręcznie, jednorazowo. Tworzy bucket S3 na zdalny state Terraform, OIDC provider dla GitHub Actions oraz rolę IAM przyjmowaną przez pipeline. State tej części jest lokalny - bucket na state nie może przechowywać własnego stanu, zanim powstanie.

Przed uruchomieniem pipeline'u CI/CD należy wskazać, z którego repozytorium GitHub Actions może przyjąć rolę IAM. W pliku `bootstrap/main.tf`, w trust policy roli, znajduje się placeholder:

```hcl
"token.actions.githubusercontent.com:sub" = "repo:ZMIEN_MNIE/ZMIEN_MNIE:ref:refs/heads/main"
```

Należy podmienić `ZMIEN_MNIE/ZMIEN_MNIE` na własną nazwę w formacie `wlasciciel/nazwa-repo` (zgodnie z dokładną nazwą repozytorium na GitHubie - wielkość liter ma znaczenie), a następnie ponownie uruchomić `terraform apply` w katalogu `bootstrap/`, aby zaktualizować warunek zaufania roli. Bez tego kroku pipeline nie uzyska dostępu do AWS.

**`infra/`** - właściwa infrastruktura podzielona na moduły per usługa (VPC, ECR, ECS, DynamoDB, S3, SQS, Lambda, API Gateway). State przechowywany zdalnie w buckecie utworzonym przez bootstrap.

Lambdy są pakowane do archiwów ZIP przez Terraform (`archive_file`) i wdrażane w ramach `terraform apply`.

---

## CI/CD

Pipeline (`.github/workflows/deploy.yml`) uwierzytelnia się w AWS przez OIDC - bez statycznych kluczy w sekretach. GitHub wystawia krótkożyjący token, a zaufanie po stronie AWS jest ograniczone do konkretnego repozytorium.

**Pull request - > `main`:** testy, `terraform fmt -check`, `validate`, `plan`. Podgląd zmian bez wdrażania.

**Push - > `main`:** po przejściu testów i bramek jakości wykonywany jest `terraform apply`, build i push obrazu do ECR, a następnie wymuszony redeploy serwisu ECS.

---

## Uruchomienie

Wymagania: konto AWS, AWS CLI, Terraform, Docker.

```bash
# 1. Fundament (raz, ręcznie) - bucket na state, OIDC, rola CI
cd bootstrap
terraform init
terraform apply

# 2. Główna infrastruktura
cd ../infra
terraform init
terraform apply
```

Po wdrożeniu adres aplikacji znajduje się w outputach Terraform (`api_gateway_url`).

---


## Co było trudne

- **Problem "jajko i kura" przy state Terraform** - zdalny state ma być w buckecie S3, ale ten bucket też trzeba czymś utworzyć. Rozwiązane przez osobny katalog `bootstrap/` z lokalnym stanem, tworzący bucket i zasoby pod CI, zanim główna infrastruktura zacznie używać zdalnego backendu.
- **Niespójny kontrakt wiadomości między Lambdami** - producent i konsument w kolejce muszą zgadzać się co do formatu wiadomości; rozjazd pól sprawiał, że druga Lambda dostawała puste dane mimo że "wszystko działało". 
- **Konfiguracja i wdrażanie zasobów AWS ręcznie** - zanim infrastruktura trafiła do Terraform, każdy element (ECS, ALB, Lambda, S3, SQS, role IAM) był stawiany ręcznie w konsoli, co pozwoliło zrozumieć zależności między usługami i uprawnienia, których wymagają.

---

## Czego się nauczyłem

- Budowy architektury event-driven na AWS (S3 - > Lambda - > SQS - > Lambda) i tego, że największym ryzykiem jest niespójny kontrakt wiadomości między producentem a konsumentem
- Pisania Terraform w modułach oraz przekazywania zmiennych i outputów między nimi
- Rozdzielenia infrastruktury na bootstrap (state backend, tożsamość pod CI) i właściwą infrastrukturę, oraz dlaczego state bootstrapu musi być lokalny
- Konfiguracji uprawnień IAM między usługami - role dla zadań ECS i funkcji Lambda, dostęp do DynamoDB, S3 i SQS
- Konteneryzacji aplikacji i wdrażania jej na ECS Fargate 

---

## Plany na przyszłość

### Bezpieczeństwo i obserwowalność (bardzo ważne)
- Zabezpieczenie przed SSRF w Lambdzie pobierającej metadane - blokada adresów wewnętrznych (m.in. endpointu metadata AWS) przed pobraniem dowolnego URL-a podanego przez użytkownika
- Monitoring i obserwowalność: CloudWatch (dashboard, alarmy na błędy Lambd i wykorzystanie ECS), docelowo distributed tracing przez X-Ray przez cały łańcuch zdarzeń

### Pozostałe
- Dead Letter Queue dla SQS - wiadomości, których Lambda nie przetworzy po kilku próbach, trafiają do osobnej kolejki zamiast krążyć w nieskończoność
- Rozdział środowisk dev/prod (osobne workspace'y / katalogi Terraform z odseparowanym state)
- Zawężenie uprawnień roli CI z `AdministratorAccess` do least-privilege