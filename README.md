# FIAPX Infraestrutura (`fiapx-infra`)

Repositório responsável por provisionar e manter toda a base de infraestrutura e observabilidade da solução FIAPX na AWS/EKS.

---

## Objetivo

Este repositório entrega:

- Infraestrutura AWS via Terraform
- Plataforma Kubernetes (EKS) pronta para os microsserviços
- Mensageria (RabbitMQ)
- Banco relacional (PostgreSQL RDS)
- Observabilidade (Prometheus + Grafana)
- Pipeline de aplicação de infraestrutura e manifests base

---

## Desenho completo da arquitetura

Para deixar a documentação mais clara, separei em **duas visões complementares**:

- `architecture.mmd`: mostra **quem são os componentes** e como eles se conectam
- `processing-sequence.mmd`: mostra **a ordem exata do fluxo E2E**, do upload até a conclusão

### Visão estrutural da solução

```mermaid
flowchart LR
  classDef actor fill:#E8F0FE,stroke:#1A73E8,color:#0B1F33,stroke-width:2px;
  classDef service fill:#E6F4EA,stroke:#188038,color:#102A12,stroke-width:1.5px;
  classDef data fill:#FEF7E0,stroke:#F9AB00,color:#3C2F00,stroke-width:1.5px;
  classDef ops fill:#F3E8FD,stroke:#9334E6,color:#2A123C,stroke-width:1.5px;

  USER[Cliente<br/>Bruno / Insomnia]

  subgraph PROD["Produção / AWS"]
    subgraph RUNTIME["EKS / namespace fiapx"]
      INGRESS[Ingress NGINX<br/>entrada única]
      API[fiapx API<br/>valida upload e orquestra]
      MQ[RabbitMQ<br/>fila de processamento]
      WORKER[fiapx-ms-processing<br/>consumidor assíncrono]
      PROM[Prometheus]
      GRAF[Grafana]
    end

    subgraph DATA["Persistência e arquivos"]
      RDS[(PostgreSQL RDS<br/>metadados e status)]
      S3[(Amazon S3<br/>vídeo original e artefatos)]
    end

    subgraph DELIVERY["Entrega / operação"]
      GH[GitHub Actions]
      ECR[Amazon ECR]
      OPS[Terraform / kubectl / Helm]
    end
  end

  USER -->|1. Envia requisição| INGRESS
  USER -. acompanha métricas .-> GRAF

  INGRESS -->|2. Encaminha /api| API
  API -->|3. Salva metadados e status| RDS
  API -->|4. Salva vídeo original| S3
  API -->|5. Publica evento| MQ

  MQ -->|6. Dispara processamento assíncrono| WORKER
  WORKER -->|7. Lê vídeo e grava frames/saídas| S3
  WORKER -->|8. Notifica conclusão| API

  PROM -->|coleta métricas| API
  PROM -->|coleta métricas| WORKER
  PROM -->|coleta métricas| MQ
  GRAF -->|consulta dashboards| PROM

  GH -->|build e push| ECR
  GH -->|provisiona e aplica| OPS
  OPS -->|deploy| API
  OPS -->|deploy| WORKER
  OPS -->|instala| MQ
  OPS -->|instala| PROM
  OPS -->|instala| GRAF

  class USER actor;
  class INGRESS,API,MQ,WORKER,PROM,GRAF service;
  class RDS,S3 data;
  class GH,ECR,OPS ops;
```

### Fluxo E2E da captura até a conclusão

```mermaid
sequenceDiagram
  autonumber
  actor Cliente
  participant Ingress as Ingress NGINX
  participant API as fiapx API
  participant DB as PostgreSQL RDS
  participant S3 as Amazon S3
  participant MQ as RabbitMQ
  participant Worker as fiapx-ms-processing

  Cliente->>Ingress: POST /api/capturas (multipart)
  Ingress->>API: Encaminha upload
  API->>DB: Cria registro da captura
  API->>S3: Salva vídeo original
  API->>MQ: Publica mensagem de processamento

  Note over API,MQ: Daqui em diante o fluxo é assíncrono

  Worker->>MQ: Consome mensagem
  Worker->>S3: Lê vídeo original
  Worker->>Worker: Processa vídeo com FFmpeg/JavaCV
  Worker->>S3: Salva frames e artefatos gerados
  Worker->>API: Notifica conclusão/resultado
  API->>DB: Atualiza status final
  Cliente->>API: GET /api/capturas
  API-->>Cliente: Retorna status e metadados
```

### Leitura rápida do fluxo

1. O **upload entra pela API**
2. A **API salva o vídeo no S3 diretamente**
3. A **API grava status/metadados no PostgreSQL**
4. A **API publica uma mensagem no RabbitMQ**
5. O **worker consome a fila de forma assíncrona**
6. O **worker lê do S3, processa e grava os artefatos de volta no S3**
7. O **worker notifica a API**, que atualiza o status final

---

## Responsabilidade de cada peça

### Terraform (`terraform/`)

- Provisiona VPC, subnets públicas/privadas, NAT, route tables
- Provisiona EKS (cluster + node group)
- Provisiona ECR dos serviços
- Provisiona bucket S3 de vídeos/frames
- Provisiona RDS PostgreSQL
- Instala charts Helm:
  - `ingress-nginx`
  - `kube-prometheus-stack`
  - `rabbitmq`

### Manifests Kubernetes (`k8s/`)

- `namespace.yaml`: namespace padrão da solução
- `secrets.yaml`: template de secret compartilhado pelos serviços
- `ingress.yaml`: exposição da API via `/api`
- `monitoring/ingress-grafana.yaml`: exposição do Grafana via `/grafana`
- `monitoring/dashboard-e2e-fiapx.yaml`: dashboard E2E provisionado automaticamente

### Workflow de infraestrutura (`.github/workflows/infra.yml`)

- bootstrap idempotente do bucket de state Terraform
- `terraform init/plan/apply`
- extração de outputs (EKS, ECR, S3, RDS)
- aplicação de manifests no cluster
- hardening automático:
  - garante regra de SG EKS -> RDS (porta 5432)
  - resolve/fallback do `DB_HOST` no secret
  - valida secret para não aplicar `DB_HOST` vazio

---

## Como a infraestrutura evita recriação desnecessária

O backend de state do Terraform é remoto em S3:

- bucket: `fiapx-terraform-state`
- key: `fiapx/terraform.tfstate`
- região: `us-east-1`

Com o mesmo state e mesma conta, o `terraform apply` faz **reconciliação** do que já existe (não recria tudo do zero), exceto quando há mudança destrutiva explícita no código ou drift que exija replace.

---

## Branches e CI/CD

Workflow de infra dispara em:

- `fix`
- `main`

Isso garante o mesmo comportamento após merge das PRs para `main`.

---

## Checklist de responsabilidade deste repositório

- [x] arquitetura e infraestrutura escalável
- [x] banco persistente (RDS)
- [x] mensageria (RabbitMQ)
- [x] monitoramento (Prometheus/Grafana)
- [x] deploy automatizado com GitHub Actions
- [x] base para os microsserviços `fiapx` e `fiapx-ms-processing`
