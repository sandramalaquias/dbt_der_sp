# DER-SP: Ocorrências e Sinistros nas Rodovias Estaduais

## Proposta

Nos trechos com mais ocorrências, há correlação com mais sinistros com vítimas fatais?
- Usar dados de 2025
- Métrica: `CORR(qtd_ocorrencias, vitimas_fatais)` por trecho (rodovia + faixa_km)
- Trechos com correlação próxima de 1 são candidatos a análise mais aprofundada pelo time de analytics

---
### Codificação da Rodovia
- Rodovia Tronco – SP_XXX  
- Acesso – SPA_XXX/XXX  
- Marginal Direita – SPM_XXX_D  
- Marginal Esquerda – SPM_XXX_E  
- Dispositivo – SPD_XXX/XXX  
- Interligação – SPI_XXX/XXX  

## Fontes de Dados

| fonte | url | formato | descrição |
|---|---|---|---|
| ocorrencias | [OCORRENCIAS.zip](https://www.der.sp.gov.br/WebSite/Arquivos/DadosAbertos/Acidentes/Ocorrencias/OCORRENCIAS.zip) | XLSX dentro de ZIP | ocorrências nas rodovias estaduais — 267.883 registros |
| malha_rodoviaria | [Sistema Rodoviário Estadual.xlsx](https://www.der.sp.gov.br/WebSite/Arquivos/DadosAbertos/MalhaRodoviariaEstadual/MalhaRodoviariaEstadual/Sistema%20Rodovi%C3%A1rio%20Estadual.xlsx) | XLSX | mapeamento rodovia + km → município — 4.583 registros |

#### Notes
> - O município é derivado da malha rodoviária via join `rodovia + km BETWEEN km_inicial AND km_final`.
> - Cobertura: 311 de 312 rodovias nas ocorrências — apenas SP-313 sem cobertura.
> - Shapefile não é necessário.
> - Os arquivos "ocorrencias" e "malha rodoviária" precisam ser convertido para parquet ou json (conteúdo invalido para csv) e depois para csv. 
> O csv será utilizado como seed. Segue o modelo para converter de xlsx para csv
> 
> Para rodovias executar:
```bash
python3 -c "
import pandas as pd
from datetime import datetime

df = pd.read_excel('files/rodovias.xlsx')
df.to_parquet('files/dim_highway.parquet', index=False)

df = pd.read_parquet('files/dim_highway.parquet')
df.columns = [' '.join(col.split()) for col in df.columns]
df['loaded_at'] = datetime.now()
df.to_csv('./seeds/dim_highway.csv', index=False, quoting=1)
"
```
> Para ocorrencias executar:
```bash
python3 -c "
import pandas as pd
from datetime import datetime

df = pd.read_excel('files/OCORRENCIAS_2025.xlsx')
df.columns = [' '.join(col.split()) for col in df.columns]
df['loaded_at'] = datetime.now()
df['dt_partition'] = datetime.now().date()
df.to_parquet('files/ocorrencias.parquet', index=False)
"
```

## Infraestrutura (Terraform)

### Storage
- S3 bucket `der-sp-bucket`
  - `raw/ocorrencias/` — dados brutos convertidos para CSV
  - `raw/rodovias/` — dados brutos convertidos para CSV

### Orquestração da Ingestão
- **Step Functions** — orquestra a ingestão sob demanda em dois passos:
  1. **Lambda** — baixa as três fontes do DER, converte XLSX para CSV e salva no S3
     - Parâmetros via variáveis de ambiente (`os.environ.get`)
     - Layer: AWSSDKPandas
     - Memória: 256MB / Timeout: 10 minutos
  2. **Glue Crawler** — cataloga os CSVs do S3 no Athena (executa após a Lambda)

### Analytics
- **Athena** — workgroup + database para consumo pelo dbt

### CI/CD
- **GitHub Actions** — executa o `dbt run` agendado ou sob demanda
  - Agendado: dia 1 de maio às 8h
  - Sob demanda: via `workflow_dispatch` (botão na aba Actions)

### Segurança
- **IAM roles** — uma role por serviço com permissões mínimas necessárias

---

## Arquitetura de Dados (dbt or run dbt-init)

```
raw/
  ocorrencias/            → dados brutos DER (CSV)
  sinistros/              → dados brutos DER (CSV)
  rodovias/               → dados brutos DER (CSV)

staging/
  stg_ocorrencias         → normaliza rodovia, km, tipo, data
  stg_sinistros           → normaliza rodovia, km, data, vítimas
  rodovias                → normaliza rodovia, km_inicial, km_final, município

core/
  core_ocorrencias_municipio   → join ocorrencias + malha → município
  core_sinistros_municipio     → join sinistros + malha → município
  core_trechos                 → join ocorrencias + sinistros por rodovia + faixa_km + ano_mes

marts/
  mart_trechos_criticos   → agregação final com correlação e rankings
```

---

## mart_trechos_criticos

Tabela final com agregação de ocorrências e sinistros por trecho de rodovia.

| rodovia | faixa_km | municipio | trecho_fronteira | municipios_trecho | qtd_ocorrencias | vitimas_fatais | correlacao | correlacao_flag | top1_tipo | top1_qtd | corr_top1 | corr_top1_flag | top2_tipo | top2_qtd | corr_top2 | corr_top2_flag | top3_tipo | top3_qtd | corr_top3 | corr_top3_flag |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 055 | 100 | Cubatão | false | null | 45 | 3 | 0.87 | HIGH | Veículo Acidentado | 18 | 0.82 | HIGH | Animal na via | 12 | 0.51 | MEDIUM | Pane mecânica | 8 | 0.21 | LOW |
| 055 | 105 | Cubatão | true | Cubatão / Santos | 30 | 2 | 0.71 | HIGH | Pane mecânica | 14 | 0.68 | MEDIUM | Animal na via | 9 | 0.30 | LOW | Veículo Acidentado | 7 | 0.18 | LOW |

### Descrição das colunas

| coluna | descrição |
|---|---|
| rodovia | número da rodovia normalizado (sem prefixo SP) |
| faixa_km | faixa de 5km agrupada — ex: 100 representa o trecho 100-105km |
| municipio | município com mais ocorrências no trecho |
| trecho_fronteira | true quando o trecho de 5km cruza divisa entre municípios |
| municipios_trecho | lista dos municípios do trecho — preenchido só quando `trecho_fronteira = true` |
| qtd_ocorrencias | total de ocorrências registradas no trecho |
| vitimas_fatais | total de vítimas fatais em sinistros no trecho |
| correlacao | coeficiente de correlação entre qtd_ocorrencias e vitimas_fatais no trecho (entre -1 e 1) |
| correlacao_flag | classificação da correlação geral: HIGH, MEDIUM ou LOW |
| top1_tipo | tipo de ocorrência mais frequente no trecho |
| top1_qtd | quantidade do tipo mais frequente |
| corr_top1 | correlação entre top1_qtd e vitimas_fatais |
| corr_top1_flag | classificação da correlação do top1: HIGH, MEDIUM ou LOW |
| top2_tipo | segundo tipo mais frequente |
| top2_qtd | quantidade do segundo tipo |
| corr_top2 | correlação entre top2_qtd e vitimas_fatais |
| corr_top2_flag | classificação da correlação do top2: HIGH, MEDIUM ou LOW |
| top3_tipo | terceiro tipo mais frequente |
| top3_qtd | quantidade do terceiro tipo |
| corr_top3 | correlação entre top3_qtd e vitimas_fatais |
| corr_top3_flag | classificação da correlação do top3: HIGH, MEDIUM ou LOW |

### Decodificação do correlacao_flag

| flag | faixa | interpretação |
|---|---|---|
| HIGH | correlacao >= 0.7 | forte correlação — trecho prioritário para análise |
| MEDIUM | correlacao >= 0.4 e < 0.7 | correlação moderada — monitorar |
| LOW | correlacao < 0.4 | correlação fraca — sem evidência de relação |

---

## Estrutura do Projeto

```
├── dbt_project.yml
├── packages.yml
├── README.md
├── models/
├── macros/
├── seeds/
├── snapshots/
├── tests/
└── analyses/
```

### Descrição das pastas

| Pasta | Descrição |
|---|---|
| `models/` | SQL transformations organized in staging, intermediate, and marts layers |
| `macros/` | Reusable Jinja/SQL functions |
| `seeds/` | Static CSV files versioned in the project |
| `snapshots/` | Historical tracking of slowly changing data |
| `tests/` | Custom data quality tests |
| `analyses/` | Ad hoc SQL queries and exploratory analysis |
| `profiles.yml` | Connection settings for dbt (stored in `~/.dbt/`, outside the project, not versioned in Git) |


##STEPS
1. completar o dbt_project
2. completar o profile.yml
3. completar o source com a raw

### Para executar: 
1. python3 -m venv .venv
2. source .venv/bin/activate
3. pip install dbt-athena-community (conector)

### comandos do dbt
- dbt init para inciar
- dbt debug para validar
- dbt clean para reiniciar o target se algum sql model path o name

optamos por full test dado o volume"


## Snapshots
Snapshots are materialized as Iceberg tables on conventional S3 + AWS Glue Catalog.
This is a target: only Icebert works for snapshots

### Note: S3 Tables as snapshot target

Using S3 Tables (table buckets) as the snapshot destination was investigated but is not currently supported by the `dbt-athena` adapter (tested on v1.10.0).

**What works natively in Athena:**

Cross-catalog CTAS from `awsdatacatalog` to `s3tablescatalog` works with `is_external = False` and no `location` property:

```sql
CREATE TABLE snp_highway
WITH (
    table_type = 'iceberg',
    format = 'parquet',
    is_external = False
)
AS SELECT * FROM awsdatacatalog.dbt_der.stg_highway;
```

**Why it fails with dbt:**

The dbt-athena snapshot macros hardcode `awsdatacatalog` in the generated SQL regardless of the `database` setting in the target profile:

```sql
from "awsdatacatalog"."dbt_der_snapshots"."snp_highway"
merge into "awsdatacatalog"."dbt_der_snapshots"."snp_highway" as dbt_internal_dest
```

This is a known limitation tracked in [dbt-adapters issue #1186](https://github.com/dbt-labs/dbt-adapters/issues/1186).

> [!NOTE]
> Since this is a personal study project, maintenance jobs are not scheduled. In a production environment, the following tasks would be required periodically to keep Iceberg tables healthy on conventional S3:

> - Compaction — merges small files into larger ones to improve query performance  
> - Vacuum — removes old snapshot files and delete files no longer referenced by any active snapshot, freeing S3 space  
> - Orphan file removal — removes files no longer referenced by any snapshot  

> These jobs would typically run as scheduled AWS Glue Jobs with PySpark. With S3 Tables, all three are handled automatically by AWS.  

Config Path para Athena
> s3_staging_dir — em profile para query results do Athena ✅
> s3_data_dir — em profile para path base para tabelas temporárias (__dbt_tmp) ✅
> external_location - em model garante que a tabela final vai para o path correto