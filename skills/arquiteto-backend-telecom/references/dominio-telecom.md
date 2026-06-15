# Glossário do Domínio — Telecomunicações

Este documento descreve as entidades, conceitos e operações típicas do domínio de uma operadora de telecomunicações brasileira que oferece banda larga via fibra óptica e telefonia móvel 4G/5G.

Quando o usuário pedir para modelar uma dessas entidades, comece daqui. Tudo aqui está em **português** (vocabulário do domínio). Toda definição é como o time de Vendas, Atendimento ou Regulatório fala.

## Áreas do negócio

### Vendas

Responsável pela aquisição de novos clientes e expansão da base. Operações típicas:

- Apresentar **ofertas** disponíveis (combinações de planos, descontos, fidelização).
- Verificar **viabilidade técnica** (existe fibra no endereço? cobertura móvel?).
- **Contratar** plano: criar assinante, agendar instalação (fibra) ou ativar chip (móvel).
- **Portabilidade**: receber número de outra operadora.
- Gerenciar **leads** e **propostas**.

### Atendimento ao Cliente

Responsável pela base instalada: suporte, mudanças contratuais, cobrança. Operações típicas:

- Consultar **contexto** do assinante (visão 360°).
- **Suspender** ou **bloquear** linha (por solicitação, fraude, roubo, inadimplência).
- **Cancelar** contrato.
- **Mudar plano** (upgrade, downgrade, migração entre tecnologias).
- Tratar **inadimplência**, gerar segunda via de **boleto**.
- Acionar **garantia** de equipamento, agendar **visita técnica**.
- Consultar **consumo** (dados, voz, SMS) e **franquia** restante.

A separação entre Vendas e Atendimento é organizacional, **não** necessariamente tecnológica. Um mesmo serviço backend pode atender as duas áreas. A distinção importa para entender o vocabulário (Vendas fala em "lead", "proposta", "viabilidade"; Atendimento fala em "protocolo", "ocorrência", "abertura de chamado").

## Produtos

### Banda Larga (Fibra Óptica)

Internet residencial ou empresarial entregue por fibra óptica. Características relevantes:

- **Atrelada a um endereço** físico, não a uma pessoa móvel.
- Requer **instalação** com técnico (agendamento, ONT, roteador).
- **Velocidade** contratada (download/upload em Mbps ou Gbps).
- **Viabilidade técnica** depende de cobertura no endereço.
- Equipamento: **ONT** (Optical Network Terminal), **roteador WiFi**.
- Termo "**ponto**" é comum: "ativar um ponto", "ponto de instalação".

### Telefonia Móvel (4G / 5G)

Linha móvel pré-paga ou pós-paga. Características relevantes:

- **MSISDN** (número de telefone, ex: 5511999998888) identifica a linha.
- **ICCID** identifica o chip físico (SIM).
- **IMEI** identifica o aparelho.
- **IMSI** identifica o assinante na rede (não exposto ao cliente final).
- **Cobertura** depende da região (4G mais ampla, 5G em expansão).
- **Tecnologia** suportada por aparelho (alguns só 4G, outros 5G NSA, outros 5G SA).
- **Portabilidade**: número pode vir de / ir para outra operadora.
- **Pré-pago** usa **recarga**. **Pós-pago** usa **fatura mensal**.

## Entidades centrais

### `Assinante`

A pessoa (física ou jurídica) que tem contrato com a operadora. **Não traduzir** para "subscriber" ou "customer".

Atributos típicos:
- `id` (UUID interno)
- `cpf` (pessoa física) ou `cnpj` (pessoa jurídica)
- `nome` / `razao_social`
- `email`
- `telefone_contato`
- `data_cadastro`
- `situacao_cadastral` (enum: ATIVA, INATIVA, BLOQUEADA, EM_ANALISE)
- `endereco_cobranca` (pode ser diferente do endereço de instalação)

Um assinante pode ter **N linhas** (móvel) e **N pontos** (fibra). Mesmo CPF pode ser dono de várias linhas.

### `Linha` (Móvel)

A unidade de serviço de telefonia móvel. Identificada pelo **MSISDN**.

Atributos típicos:
- `id` (UUID interno)
- `msisdn` (número, ex: 5511999998888)
- `iccid` (chip)
- `imsi` (identificador na rede)
- `assinante_id`
- `plano_codigo` (referência ao plano atual)
- `tipo` (PRÉ_PAGO, PÓS_PAGO, CONTROLE)
- `situacao` (enum: `SituacaoLinha`)
- `data_ativacao`
- `data_ultima_recarga` (se pré-pago)

`SituacaoLinha` (enum padrão do domínio):
- `ATIVA`: usável
- `SUSPENSA`: usuário solicitou suspensão temporária
- `BLOQUEADA`: bloqueio operacional (por inadimplência, fraude, perda/roubo)
- `CANCELADA`: terminada permanentemente
- `PORTABILIDADE_EM_ANDAMENTO`: número saindo para outra operadora ou vice-versa

`MotivoSuspensao` / `MotivoBloqueio` (importante distinguir):
- `INADIMPLENCIA`
- `SOLICITACAO_CLIENTE`
- `FRAUDE_SUSPEITA`
- `ROUBO_OU_PERDA`

**Bloqueio ≠ Suspensão.** São operações distintas no domínio:
- Suspensão é tipicamente a pedido do cliente (viagem, perda do chip mas vai recuperar). É reversível pelo cliente.
- Bloqueio é decisão da operadora (inadimplência, fraude, roubo confirmado). Reversibilidade depende do motivo.

### `Ponto` (Banda Larga)

A unidade de serviço de internet fixa, atrelada a um **endereço**.

Atributos típicos:
- `id` (UUID interno)
- `assinante_id`
- `endereco_instalacao`
- `cep`
- `plano_codigo`
- `situacao` (enum: ATIVA, SUSPENSA, BLOQUEADA, CANCELADA, INSTALACAO_PENDENTE)
- `data_instalacao`
- `velocidade_contratada_mbps`
- `equipamentos` (ONT, roteador — IDs de equipamento)
- `tecnologia` (GPON, XGS-PON, etc.)

### `Plano`

O produto comercial. Diferente para fibra e móvel.

**Plano Móvel:**
- `codigo`, `nome`, `valor_mensal`
- `tipo` (PRÉ, PÓS, CONTROLE)
- `franquia_dados_bytes`, `franquia_voz_minutos`, `franquia_sms`
- `apps_inclusos` (WhatsApp ilimitado, redes sociais, etc.)
- `tecnologia_minima` (4G ou 5G)

**Plano Fibra:**
- `codigo`, `nome`, `valor_mensal`
- `velocidade_download_mbps`, `velocidade_upload_mbps`
- `servicos_adicionais` (TV, telefone fixo, streaming)

### `Fatura`

Documento de cobrança mensal (pós-pago e fibra).

Atributos típicos:
- `id`, `assinante_id`
- `data_emissao`, `data_vencimento`
- `valor_total`
- `codigo_barras` (boleto)
- `linha_digitavel`
- `situacao` (enum: ABERTA, PAGA, VENCIDA, CANCELADA, EM_PROCESSAMENTO)
- `itens` (lista de `ItemFatura` — assinatura, serviços adicionais, consumo excedente)

### `Recarga`

Adição de crédito a uma linha pré-paga.

Atributos típicos:
- `id`, `linha_id` (não `msisdn_id` — o ID da linha é interno)
- `valor`
- `data_recarga`
- `canal` (APP, SITE, REVENDA, RECARGA_BÔNUS)
- `situacao` (enum: PROCESSADA, FALHADA, EM_PROCESSAMENTO, ESTORNADA)
- `validade_credito` (data limite para uso)

### `Portabilidade`

Processo regulado pela Anatel para transferir um número entre operadoras.

Atributos típicos:
- `id`, `msisdn`
- `tipo` (RECEBER, ENVIAR)
- `operadora_origem` / `operadora_destino`
- `data_solicitacao`
- `data_prevista_efetivacao`
- `situacao` (enum: SOLICITADA, EM_ANALISE, APROVADA, REJEITADA, EFETIVADA, CANCELADA)
- `protocolo` (número público para o cliente acompanhar)
- `motivo_rejeicao` (quando aplicável)

A portabilidade tem **prazos regulatórios** (Resolução Anatel 460/2007) e **janelas de execução**. Detalhes operacionais ficam com o serviço de portabilidade — para esta skill, o que importa é que é uma entidade com ciclo de vida e estados bem definidos.

### `Consumo`

Uso de recursos da linha em um período.

Atributos típicos:
- `linha_id`
- `periodo` (mês de referência)
- `dados_consumidos_bytes`
- `minutos_consumidos`
- `sms_consumidos`
- `dados_franquia_bytes` (snapshot da franquia no início do ciclo)
- `dados_excedente_bytes`
- `data_ultima_atualizacao`

Consumo é atualizado por evento (CDR — Call Detail Record — do core de rede). Em geral, o serviço de consumo lê eventos e mantém os totais agregados.

### `Cobranca`

Processo de tentativa de recebimento de fatura em aberto. **Não é "billing" genérico.**

Atributos típicos:
- `id`, `fatura_id`, `assinante_id`
- `data_inicio_processo`
- `tentativas` (lista de tentativas com canal e resultado)
- `situacao` (enum: EM_NEGOCIACAO, ACORDO_FECHADO, ENCERRADA_PAGA, ENCERRADA_INADIMPLENCIA, JUDICIAL)

A cobrança costuma ser um serviço próprio com regras complexas (régua de cobrança, escalonamento, parcerias com empresas de cobrança). Para esta skill, o ponto é: **`cobranca` é vocabulário do domínio, não "billing" — não traduzir.**

## Acrônimos do domínio

Mantidos como estão, sem tradução:

- **MSISDN**: Mobile Station International Subscriber Directory Number. O número do telefone móvel completo (com código do país e DDD). Ex: `5511999998888`.
- **ICCID**: Integrated Circuit Card Identifier. Identificador do chip físico (SIM card).
- **IMSI**: International Mobile Subscriber Identity. Identificador do assinante na rede (não exposto ao cliente).
- **IMEI**: International Mobile Equipment Identity. Identificador do aparelho.
- **CPF**: Cadastro de Pessoas Físicas (Brasil). 11 dígitos.
- **CNPJ**: Cadastro Nacional da Pessoa Jurídica (Brasil). 14 dígitos.
- **CEP**: Código de Endereçamento Postal. 8 dígitos.
- **DDD**: Discagem Direta à Distância. 2 dígitos do código de área.
- **RG**: Registro Geral (identidade).
- **ANATEL**: Agência Nacional de Telecomunicações (reguladora).
- **CDR**: Call Detail Record. Evento de uso da rede.
- **ONT**: Optical Network Terminal. Equipamento na ponta da fibra na casa do cliente.
- **GPON / XGS-PON**: tecnologias de fibra (Gigabit / 10G capable).
- **APN**: Access Point Name. Configuração de rede para dados móveis.

## Conceitos importantes para modelagem

### Pré-pago vs Pós-pago vs Controle

- **Pré-pago**: o cliente recarrega antes de usar. Não tem fatura. Não tem inadimplência (não tem como ficar devendo). Tem validade de crédito.
- **Pós-pago**: o cliente usa e depois recebe fatura. Tem inadimplência possível. Pode ter franquias maiores e benefícios.
- **Controle**: híbrido. Tem mensalidade fixa pré-paga + bloqueio se exceder franquia. Mais comum no Brasil para o mercado popular.

A modelagem **deve** suportar os três. Não assumir que toda linha tem fatura, nem que toda linha tem recarga.

### Equipamentos vs Linha vs Plano

São coisas distintas e relacionáveis:

- O **plano** é o produto comercial (valor, franquia, benefícios).
- A **linha** é a unidade de serviço identificada pelo MSISDN.
- O **chip** (ICCID) é o objeto físico que vai no aparelho.
- O **aparelho** (IMEI) é o telefone do cliente.

O cliente pode **trocar de chip** mantendo o MSISDN (perda, dano, upgrade para 5G). Pode **trocar de aparelho** mantendo o chip. Pode **mudar de plano** mantendo a linha. Modelar essas relações como entidades separadas com chaves estrangeiras, não como um único registro gigante.

### Endereço

Endereço aparece em três contextos potencialmente diferentes para um mesmo assinante:

- **Endereço de cadastro** (onde mora)
- **Endereço de cobrança** (onde recebe boleto/correspondência — pode ser caixa postal, escritório)
- **Endereço de instalação** (de cada ponto de fibra — assinante pode ter mais de um)

Modelar como entidades relacionadas, não como campos repetidos.

## Operações típicas (com nomes em português)

Para referência rápida na hora de nomear RPCs. Verbos de negócio em português:

- `BuscarAssinantePorCPF`, `BuscarAssinantePorMSISDN`, `BuscarAssinantePorEmail`
- `CadastrarAssinante`, `AtualizarAssinante`, `InativarAssinante`
- `ListarLinhasDoAssinante`, `ListarPontosDoAssinante`
- `AtivarLinha`, `SuspenderLinha`, `BloquearLinha`, `ReativarLinha`, `CancelarLinha`
- `MigrarPlano`, `ConsultarPlanoAtual`
- `RegistrarRecarga`, `ListarRecargasDaLinha`, `EstornarRecarga`
- `GerarFatura`, `ListarFaturasDoAssinante`, `BuscarFaturaPorId`, `MarcarFaturaPaga`
- `IniciarPortabilidade`, `ConsultarStatusPortabilidade`, `CancelarPortabilidade`
- `ConsultarConsumoDaLinha`, `ConsultarFranquiaRestante`
- `AbrirChamado`, `ListarChamadosDoAssinante`, `FecharChamado`
- `ConsultarViabilidadeFibra` (por CEP / endereço)
- `AgendarInstalacao`, `ConfirmarInstalacao`, `ReagendarInstalacao`

**Padrões úteis:**
- `BuscarXPorY` para busca por chave única (retorna 1, erro se não acha).
- `ListarXDoY` ou `ListarXPorY` para listas (retorna N, vazio é OK).
- `ConsultarX` quando é leitura de algo derivado/agregado (saldo, status, franquia).
- Verbos de transição de estado (`Ativar`, `Suspender`, `Cancelar`) refletem máquina de estados explícita.
