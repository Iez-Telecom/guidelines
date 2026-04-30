# Convenção de Idioma no Código

Guia prático para novos membros da equipe.

## Para que serve este documento

Este documento explica como aplicamos a convenção de idioma do nosso código no dia a dia. Se você acabou de entrar no time e está estranhando ver código com nomes em português, comece por aqui.

A justificativa completa da decisão está no documento de arquitetura, na seção "Sobre convenção de idioma". O resumo: usamos português para vocabulário do domínio do negócio e inglês para vocabulário técnico da plataforma. Esta separação é deliberada e fundamentada em princípios de Domain-Driven Design. Não é mistura desorganizada — é cada conceito no seu idioma natural.

Este documento se foca no *como aplicar*, com exemplos do nosso domínio real (telecomunicações móveis).

## A regra em uma frase

Se o conceito existe no negócio (alguém do time comercial, do call center ou do regulatório), está em português. Se o conceito existe na engenharia (Go, gRPC, banco de dados, protocolos), está em inglês.

## Vocabulário do nosso domínio

Os termos abaixo são exemplos eu podem aparecerno código em português porque são vocabulário do negócio:

`assinante`, `linha`, `plano`, `recarga`, `fatura`, `cobranca`, `portabilidade`, `ativacao`, `suspensao`, `cancelamento`, `consumo`, `franquia`, `pacote`, `oferta`, `chip`, `aparelho`, `migracao`, `bloqueio`, `desbloqueio`, `inadimplencia`, `vencimento`, `parcela`, `boleto`.

Acrônimos do domínio mantemos como são, sem traduzir nem expandir: `MSISDN`, `ICCID`, `IMEI`, `IMSI`, `CPF`, `CNPJ`, `CEP`, `RG`, `DDD`, `LTE`, `5G`. São termos consagrados.

## Vocabulário técnico

Os termos abaixo são exemplos que aparecem em inglês porque são vocabulário da plataforma:

`handler`, `store`, `client`, `server`, `request`, `response`, `context`, `error`, `database`, `cache`, `config`, `logger`, `pool`, `connection`, `transaction`, `query`, `marshal`, `unmarshal`, `encode`, `decode`, `parse`, `format`, `validate` (quando é validação técnica de formato, não regra de negócio).

## Exemplos em Go

### Tipos do domínio

```go
// Bom: tipo de domínio em português
type Assinante struct {
    ID              string
    MSISDN          string
    CPF             string
    Nome            string
    DataAtivacao    time.Time
    SituacaoLinha   SituacaoLinha
    PlanoAtual      Plano
}

type Plano struct {
    Codigo          string
    Nome            string
    ValorMensal     decimal.Decimal
    FranquiaDados   int64  // em bytes
    FranquiaVoz     int    // em minutos
    FranquiaSMS     int
}

// Ruim: domínio em inglês
type Subscriber struct {
    ID              string
    PhoneNumber     string
    TaxID           string
    // ...
}
```

### Enums do domínio

```go
// Bom: estados do negócio em português
type SituacaoLinha int

const (
    SituacaoLinhaAtiva SituacaoLinha = iota
    SituacaoLinhaSuspensa
    SituacaoLinhaCancelada
    SituacaoLinhaBloqueada
    SituacaoLinhaPortabilidadeEmAndamento
)

// Ruim: traduzir os estados perde clareza com o time de operações
type LineStatus int

const (
    LineStatusActive LineStatus = iota
    LineStatusSuspended
    // ...
)
```

### Funções de regra de negócio

```go
// Bom: nomes em português refletem o que o analista de negócio diria
func calcularValorRecarga(plano Plano, valorBruto decimal.Decimal) decimal.Decimal { }

func validarPortabilidade(linhaOrigem Linha, operadoraDestino string) error { }

func aplicarFranquiaConsumo(consumo Consumo, franquia Franquia) Consumo { }

func suspenderLinhaPorInadimplencia(ctx context.Context, assinanteID string) error { }

// Ruim: tradução desnecessária do vocabulário do domínio
func calculateRechargeValue(plan Plan, grossValue decimal.Decimal) decimal.Decimal { }
```

### Funções e tipos técnicos

```go
// Bom: vocabulário técnico em inglês
func openDatabaseConnection(config Config) (*pgxpool.Pool, error) { }

type Handler struct {
    store  Store
    logger *slog.Logger
}

func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) { }

// Ruim: traduzir conceitos da plataforma cria atrito sem ganho
func abrirConexaoBanco(config Config) (*pgxpool.Pool, error) { }
```

### Métodos misturando domínio e técnica

A regra se aplica dentro de uma mesma assinatura: o nome do método é domínio, os parâmetros técnicos ficam em inglês.

```go
// Bom: método de domínio recebe context (técnico) e retorna error (técnico)
func (s *AssinanteService) BuscarPorMSISDN(ctx context.Context, msisdn string) (*Assinante, error) { }

func (s *FaturaService) GerarFaturaMensal(ctx context.Context, assinanteID string, mes time.Time) (*Fatura, error) { }

// Cliente para serviço externo: o cliente é técnico, mas os métodos são de domínio
type ClienteOperadoraDestino interface {
    SolicitarPortabilidade(ctx context.Context, req SolicitacaoPortabilidade) error
    ConsultarStatusPortabilidade(ctx context.Context, protocolo string) (StatusPortabilidade, error)
}
```

### Variáveis dentro de funções

Mesma regra: vocabulário do domínio em português, técnico em inglês. Variáveis com escopo curto podem usar abreviações comuns.

```go
func (s *AssinanteService) AtivarLinha(ctx context.Context, req AtivarLinhaRequest) error {
    // ctx, req são técnicos; assinante, linha, plano são domínio
    assinante, err := s.store.BuscarAssinante(ctx, req.AssinanteID)
    if err != nil {
        return fmt.Errorf("buscar assinante: %w", err)
    }
    
    plano, err := s.store.BuscarPlano(ctx, req.CodigoPlano)
    if err != nil {
        return fmt.Errorf("buscar plano: %w", err)
    }
    
    linha := Linha{
        MSISDN:        req.MSISDN,
        AssinanteID:   assinante.ID,
        Plano:         plano,
        Situacao:      SituacaoLinhaAtiva,
        DataAtivacao:  time.Now(),
    }
    
    return s.store.SalvarLinha(ctx, linha)
}
```

### Erros do domínio

Erros voltados ao negócio têm mensagens em português. Erros técnicos podem ficar em inglês quando são genéricos.

```go
// Erros de domínio: em português, descrevem regra de negócio
var (
    ErrAssinanteNaoEncontrado     = errors.New("assinante não encontrado")
    ErrLinhaJaAtiva               = errors.New("linha já está ativa")
    ErrPortabilidadeEmAndamento   = errors.New("já existe portabilidade em andamento para esta linha")
    ErrFranquiaInsuficiente       = errors.New("franquia insuficiente para a operação")
    ErrInadimplenciaImpedeOperacao = errors.New("inadimplência impede a operação solicitada")
)

// Ao envolver erros técnicos, mantém o contexto técnico em inglês
if err := db.QueryRow(...).Scan(&assinante); err != nil {
    if errors.Is(err, sql.ErrNoRows) {
        return ErrAssinanteNaoEncontrado
    }
    return fmt.Errorf("scan assinante row: %w", err)
}
```

## Exemplos em TypeScript

As mesmas regras se aplicam ao TypeScript no frontend: vocabulário do domínio em português, vocabulário técnico em inglês. As convenções de capitalização são as do próprio TypeScript (`PascalCase` para tipos, `camelCase` para variáveis e funções), apenas o vocabulário muda.

### Tipos e interfaces do domínio

```typescript
// Bom: tipos do domínio em português
interface Assinante {
  id: string;
  msisdn: string;
  cpf: string;
  nome: string;
  email: string | null;
  dataCadastro: Date;
  situacaoCadastral: SituacaoCadastral;
}

interface Plano {
  codigo: string;
  nome: string;
  valorMensal: number;
  franquiaDados: number;  // em bytes
  franquiaVoz: number;    // em minutos
  franquiaSMS: number;
}

interface Linha {
  id: string;
  msisdn: string;
  iccid: string;
  assinanteId: string;
  planoAtual: Plano;
  situacao: SituacaoLinha;
  dataAtivacao: Date | null;
}

// Ruim: domínio em inglês
interface Subscriber {
  id: string;
  phoneNumber: string;
  taxId: string;
  // ...
}
```

### Enums do domínio

```typescript
// Bom: estados do negócio em português
enum SituacaoLinha {
  Ativa = 'ATIVA',
  Suspensa = 'SUSPENSA',
  Cancelada = 'CANCELADA',
  Bloqueada = 'BLOQUEADA',
  PortabilidadeEmAndamento = 'PORTABILIDADE_EM_ANDAMENTO',
}

enum MotivoSuspensao {
  Inadimplencia = 'INADIMPLENCIA',
  SolicitacaoCliente = 'SOLICITACAO_CLIENTE',
  FraudeSuspeita = 'FRAUDE_SUSPEITA',
  RouboOuPerda = 'ROUBO_OU_PERDA',
}

// Em TypeScript moderno, union types de string literais são frequentemente
// preferíveis a enums. A regra de idioma se aplica igualmente:
type SituacaoLinha = 
  | 'ATIVA' 
  | 'SUSPENSA' 
  | 'CANCELADA' 
  | 'BLOQUEADA' 
  | 'PORTABILIDADE_EM_ANDAMENTO';
```

### Funções de regra de negócio

```typescript
// Bom: nomes em português refletem o vocabulário do negócio
function calcularValorRecarga(plano: Plano, valorBruto: number): number {
  // ...
}

function validarPortabilidade(
  linhaOrigem: Linha, 
  operadoraDestino: string,
): ResultadoValidacao {
  // ...
}

function aplicarFranquiaConsumo(consumo: Consumo, franquia: Franquia): Consumo {
  // ...
}

async function suspenderLinhaPorInadimplencia(assinanteId: string): Promise<void> {
  // ...
}

// Ruim: tradução desnecessária do vocabulário do domínio
function calculateRechargeValue(plan: Plan, grossValue: number): number {
  // ...
}
```

### Classes e métodos

```typescript
// Bom: classe de domínio em português, padrões técnicos em inglês
class AssinanteService {
  constructor(
    private readonly client: ApiClient,
    private readonly logger: Logger,
  ) {}

  async buscarPorMSISDN(msisdn: string): Promise<Assinante | null> {
    // ...
  }

  async cadastrar(dados: DadosCadastroAssinante): Promise<Assinante> {
    // ...
  }

  async atualizarSituacaoCadastral(
    assinanteId: string,
    novaSituacao: SituacaoCadastral,
  ): Promise<void> {
    // ...
  }
}
```

Note que `constructor`, `private`, `readonly`, `async`, `Promise` ficam em inglês porque são vocabulário do TypeScript. Os nomes da classe (`AssinanteService`) e dos métodos (`buscarPorMSISDN`, `cadastrar`) são domínio, em português.

### Variáveis dentro de funções

```typescript
async function ativarLinha(req: AtivarLinhaRequest): Promise<void> {
  // req e response são técnicos; assinante, linha, plano são domínio
  const assinante = await assinanteService.buscarPorId(req.assinanteId);
  if (!assinante) {
    throw new ErroAssinanteNaoEncontrado(req.assinanteId);
  }

  const plano = await planoService.buscarPorCodigo(req.codigoPlano);
  if (!plano) {
    throw new ErroPlanoNaoEncontrado(req.codigoPlano);
  }

  const novaLinha: Linha = {
    id: crypto.randomUUID(),
    msisdn: req.msisdn,
    iccid: req.iccid,
    assinanteId: assinante.id,
    planoAtual: plano,
    situacao: 'ATIVA',
    dataAtivacao: new Date(),
  };

  await linhaService.salvar(novaLinha);
}
```

### Erros do domínio

```typescript
// Erros de domínio: classes em português, descrevem regras de negócio
class ErroAssinanteNaoEncontrado extends Error {
  constructor(public readonly assinanteId: string) {
    super(`Assinante não encontrado: ${assinanteId}`);
    this.name = 'ErroAssinanteNaoEncontrado';
  }
}

class ErroLinhaJaAtiva extends Error {
  constructor(public readonly msisdn: string) {
    super(`Linha já está ativa: ${msisdn}`);
    this.name = 'ErroLinhaJaAtiva';
  }
}

class ErroFranquiaInsuficiente extends Error {
  constructor(
    public readonly franquiaDisponivel: number,
    public readonly franquiaNecessaria: number,
  ) {
    super(
      `Franquia insuficiente: disponível ${franquiaDisponivel}, ` +
      `necessária ${franquiaNecessaria}`,
    );
    this.name = 'ErroFranquiaInsuficiente';
  }
}

// Erros técnicos genéricos podem ficar em inglês
class NetworkError extends Error { /* ... */ }
class ValidationError extends Error { /* ... */ }
```

### Componentes de UI (quando aplicável)

Componentes de interface são casos interessantes: eles representam algo de domínio (`PerfilAssinante`, `ListaLinhas`) mas também são entidades técnicas do framework. A regra que se sustenta: o nome do componente reflete o que ele representa no domínio.

```typescript
// Bom: componentes nomeados pelo conceito de domínio que representam
function PerfilAssinante({ assinante }: { assinante: Assinante }) {
  return (
    <div>
      <h1>{assinante.nome}</h1>
      <p>CPF: {assinante.cpf}</p>
    </div>
  );
}

function ListaLinhasDoAssinante({ assinanteId }: { assinanteId: string }) {
  // ...
}

function FormularioCadastroAssinante({ onSubmit }: Props) {
  // ...
}

// Props específicas são tipos do domínio, em português
interface PerfilAssinanteProps {
  assinante: Assinante;
  onEditar?: () => void;
  exibirHistorico?: boolean;
}
```

Note que `props`, `children`, `onClick`, `onSubmit`, `useState`, `useEffect` ficam em inglês porque são vocabulário do framework. Os nomes dos componentes e suas props específicas de domínio ficam em português.

### Chamadas a APIs

Quando o frontend consome a API gRPC do backend, a tradução de campos é importante. Se o backend expõe `BuscarAssinantePorMSISDN`, o cliente TypeScript deve preservar esse nome.

```typescript
// Bom: nomes alinhados entre backend e frontend
const cliente = new ServicoAssinantesClient(transport);

const response = await cliente.buscarAssinantePorMSISDN({
  msisdn: '5511999998888',
});

const assinante = response.assinante;
```

A consistência entre as camadas (proto → backend Go → cliente TypeScript → componentes) é o que torna a Linguagem Ubíqua útil. Se quebra em qualquer ponto, o benefício se perde.

### Testes

```typescript
// Descrições de teste em português, espelhando como o time fala da regra
describe('AssinanteService', () => {
  describe('ativarLinha', () => {
    it('deve ativar uma linha com sucesso quando todos os dados são válidos', async () => {
      // ...
    });

    it('deve lançar erro quando assinante não é encontrado', async () => {
      // ...
    });

    it('deve lançar erro quando linha já está ativa', async () => {
      // ...
    });

    it('não deve permitir ativação se assinante está em situação de inadimplência', async () => {
      // ...
    });
  });
});
```

## Exemplos em Protobuf

### Serviços e RPCs

Nomes de serviços e RPCs são operações de domínio — em português. `Request` e `Response` são sufixos técnicos do gRPC — em inglês.

```protobuf
service ServicoAssinantes {
  rpc BuscarAssinantePorMSISDN(BuscarAssinantePorMSISDNRequest)
      returns (BuscarAssinantePorMSISDNResponse);
  
  rpc CadastrarAssinante(CadastrarAssinanteRequest)
      returns (CadastrarAssinanteResponse);
  
  rpc AtivarLinha(AtivarLinhaRequest)
      returns (AtivarLinhaResponse);
  
  rpc SuspenderLinhaPorInadimplencia(SuspenderLinhaPorInadimplenciaRequest)
      returns (SuspenderLinhaPorInadimplenciaResponse);
  
  rpc IniciarPortabilidade(IniciarPortabilidadeRequest)
      returns (IniciarPortabilidadeResponse);
}
```

Note que evitamos prefixos como `Get`, `Create`, `Update`, `Delete`. Usamos `Buscar`, `Cadastrar`, `Atualizar`, `Cancelar` porque é o que o analista de negócio diria. A inconsistência seria misturar `GetAssinante` com `CadastrarAssinante` no mesmo serviço.

### Mensagens

Tipos de domínio em português. Sufixos `Request`/`Response` em inglês.

```protobuf
message Assinante {
  string id = 1;
  string cpf = 2;
  string nome = 3;
  string email = 4;
  google.protobuf.Timestamp data_cadastro = 5;
  SituacaoCadastral situacao_cadastral = 6;
}

message Linha {
  string id = 1;
  string msisdn = 2;
  string iccid = 3;
  string assinante_id = 4;
  Plano plano_atual = 5;
  SituacaoLinha situacao = 6;
  google.protobuf.Timestamp data_ativacao = 7;
}

message BuscarAssinantePorMSISDNRequest {
  string msisdn = 1;
}

message BuscarAssinantePorMSISDNResponse {
  Assinante assinante = 1;
  repeated Linha linhas = 2;
}
```

### Enums

```protobuf
enum SituacaoLinha {
  SITUACAO_LINHA_NAO_ESPECIFICADA = 0;
  SITUACAO_LINHA_ATIVA = 1;
  SITUACAO_LINHA_SUSPENSA = 2;
  SITUACAO_LINHA_CANCELADA = 3;
  SITUACAO_LINHA_BLOQUEADA = 4;
  SITUACAO_LINHA_PORTABILIDADE_EM_ANDAMENTO = 5;
}

enum MotivoSuspensao {
  MOTIVO_SUSPENSAO_NAO_ESPECIFICADO = 0;
  MOTIVO_SUSPENSAO_INADIMPLENCIA = 1;
  MOTIVO_SUSPENSAO_SOLICITACAO_CLIENTE = 2;
  MOTIVO_SUSPENSAO_FRAUDE_SUSPEITA = 3;
  MOTIVO_SUSPENSAO_ROUBO_OU_PERDA = 4;
}
```

### Campos

Nomes de campos em `snake_case` (convenção do protobuf), mas o vocabulário segue a regra: domínio em português, técnico em inglês.

```protobuf
message Fatura {
  string id = 1;
  string assinante_id = 2;
  google.protobuf.Timestamp data_emissao = 3;
  google.protobuf.Timestamp data_vencimento = 4;
  string codigo_barras = 5;
  decimal valor_total = 6;
  repeated ItemFatura itens = 7;
  SituacaoFatura situacao = 8;
}
```

## Exemplos em Banco de Dados

### Tabelas e colunas

Mesma regra: domínio em português, técnico em inglês quando aplicável.

```sql
CREATE TABLE assinantes (
    id              UUID PRIMARY KEY,
    cpf             VARCHAR(11) NOT NULL UNIQUE,
    nome            TEXT NOT NULL,
    email           TEXT,
    data_cadastro   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    situacao_cadastral SMALLINT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE linhas (
    id              UUID PRIMARY KEY,
    msisdn          VARCHAR(13) NOT NULL UNIQUE,
    iccid           VARCHAR(20) NOT NULL UNIQUE,
    assinante_id    UUID NOT NULL REFERENCES assinantes(id),
    plano_codigo    VARCHAR(20) NOT NULL REFERENCES planos(codigo),
    situacao        SMALLINT NOT NULL,
    data_ativacao   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_linhas_assinante_id ON linhas(assinante_id);
CREATE INDEX idx_linhas_situacao ON linhas(situacao);
```

Note que `created_at`, `updated_at`, `id` ficam em inglês porque são convenções técnicas. `assinante_id`, `data_ativacao`, `situacao` são domínio, em português.

### Queries do sqlc

```sql
-- name: BuscarAssinantePorCPF :one
SELECT * FROM assinantes
WHERE cpf = $1;

-- name: ListarLinhasDoAssinante :many
SELECT * FROM linhas
WHERE assinante_id = $1
ORDER BY data_ativacao DESC;

-- name: AtualizarSituacaoLinha :exec
UPDATE linhas
SET situacao = $2,
    updated_at = NOW()
WHERE id = $1;
```

Os nomes das queries (que viram nomes de funções no código gerado) seguem a mesma regra: operações de domínio em português.

## Logs e Mensagens

### Logs estruturados

Chaves em inglês (convenção do ecossistema, e ferramentas de observabilidade esperam isso). Valores podem ser de qualquer idioma.

```go
// Bom: chaves técnicas em inglês, valores podem ser do domínio
logger.Info("linha ativada com sucesso",
    "assinante_id", assinante.ID,
    "msisdn", linha.MSISDN,
    "plano", plano.Codigo,
)

logger.Error("falha ao processar portabilidade",
    "error", err,
    "protocolo", protocolo,
    "operadora_origem", operadora,
)
```

### Mensagens voltadas ao usuário final

Sempre em português, sem ambiguidade. Não traduzir on-the-fly de mensagens em inglês.

```go
// Bom: mensagem direta em português
return fmt.Errorf("não é possível ativar a linha: assinante possui inadimplência")

// Ruim: tradução literal de mensagem técnica em inglês
return fmt.Errorf("não pode ativar linha: subscriber tem outstanding balance")
```

## Casos Limítrofes

### Termos que parecem técnicos mas são do domínio

Alguns conceitos parecem genéricos mas têm significado específico no nosso domínio. Se o significado é específico, é domínio.

`Cobranca` não é "billing" genérico — é o processo específico de tentar receber um valor em aberto, com regras do nosso negócio. Em português.

`Bloqueio` não é "lock" genérico — é uma ação específica sobre uma linha, distinta de `Suspensao`. Em português.

`Recarga` não é "refill" — é uma operação específica de adicionar crédito a uma linha pré-paga. Em português.

### Termos do domínio que viraram técnicos

O contrário também acontece. Alguns termos começaram no domínio mas viraram convenção técnica universal. Quando isso acontece, ficam em inglês.

`Token` (de autenticação) é universal. Em inglês.

`Session` é universal. Em inglês.

`Webhook` é universal. Em inglês.

`Cache` é universal. Em inglês.

A regra prática: se você procurar o termo em documentação técnica de qualquer empresa do mundo e achar o mesmo significado, é técnico. Se o termo só faz sentido no contexto do nosso negócio, é domínio.

### Abreviações

Acrônimos do domínio brasileiro são mantidos: `CPF`, `CNPJ`, `CEP`, `DDD`. Acrônimos técnicos universais também: `URL`, `HTTP`, `JSON`, `UUID`. Acrônimos do nosso negócio específico ficam como são: `MSISDN`, `ICCID`, `IMEI`, `IMSI`.

### Inglês "infiltrado" no português coloquial

Algumas palavras em inglês entraram no português técnico brasileiro e usar a tradução literal soaria estranho. Aceitáveis em inglês: `link`, `site`, `feed`, `dashboard`, `deploy`, `release`. Estes são casos de exceção, não a regra.

## Erros Comuns para Evitar

**Misturar idiomas no mesmo conceito.** O pior dos dois mundos é ter `Cliente` no proto e `CustomerService` no nome do RPC, ou `assinante` no código mas `subscriber_id` no banco. Se um termo é do domínio, é em português em *todas* as camadas.

**Traduzir literalmente termos técnicos consagrados.** "Manipulador" para `Handler`, "Despachante" para `Dispatcher`, "Repositório" para `Repository` são tecnicamente português mas soam estranho mesmo para falantes nativos. Mantenha em inglês.

**Tentar parecer "profissional" usando inglês onde português serviria melhor.** Se o time de operações fala "linha suspensa por inadimplência", o código deve falar a mesma coisa. Traduzir para "line suspended due to default" não deixa o código mais profissional, deixa mais distante do negócio.

**Usar inglês em mensagens de erro voltadas ao usuário.** O usuário final fala português. O time de suporte fala português. As mensagens devem estar em português.

**Aceitar sugestões de IA sem revisar.** Ferramentas como Gemini, Claude e ChatGPT vão sugerir nomes em inglês por padrão. Ao usar essas ferramentas, sempre revise nomes de domínio e converta para português antes de aceitar a sugestão. Pode incluir na sua instrução para a IA: "use nomes em português para conceitos do domínio (assinante, linha, fatura, recarga, etc.) e inglês para conceitos técnicos."

## Quando Tiver Dúvida

A pergunta a se fazer é: "se eu mostrasse esse código para alguém do call center, do time comercial, ou do regulatório, ele reconheceria o conceito?" Se sim, é domínio — em português. Se a pessoa precisaria de explicação técnica para entender o conceito, é técnico — em inglês.

Outra pergunta útil: "esse termo aparece em documentos do nosso negócio, em conversas com o time não-técnico, em comunicação com clientes, em obrigações regulatórias?" Se sim, é vocabulário do domínio. Mantenha em português para que o código fale a mesma língua.

Em caso de dúvida real entre as duas opções, traga para discussão em revisão de código. É melhor ter uma discussão de cinco minutos sobre nomenclatura do que estabelecer um padrão errado que vai ser copiado por anos.

## Recursos

A justificativa filosófica completa da decisão está no documento de arquitetura, seção "Sobre convenção de idioma".

Para quem quer entender o conceito de Linguagem Ubíqua de DDD, o livro original de Eric Evans (*Domain-Driven Design*, 2003) é a referência. Não é leitura obrigatória — este documento é suficiente para o dia a dia. Mas para quem quiser aprofundar o porquê, a fonte está lá.