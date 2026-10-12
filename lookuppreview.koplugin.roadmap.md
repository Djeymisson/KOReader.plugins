# Lookup Preview — Roadmap

Plano de evolução do [Lookup Preview](./lookuppreview.koplugin.md), ordenado pelo valor percebido de cada mudança. Este arquivo é atualizado a cada entrega: marque o item, preencha a versão e anote o que mudou em relação ao planejado.

**Legenda:** ⬜ pendente · 🟨 em andamento · ✅ concluído · ⏸️ adiado · ❌ descartado
**Valor:** ★ (baixo) a ★★★★★ (alto) · **Esforço:** Baixo / Médio / Alto

Versão atual: **v1.5.0**

## Entregas

| Versão | Conteúdo | Status |
|---|---|---|
| v1.1.0 | Fase 0 + 1.1 + 1.2 | ✅ |
| v1.2.0 | 1.3 + 1.4 + D.1 | ✅ |
| v1.3.0 | Fase 2 | ✅ |
| v1.4.0 | Fase 3 + D.2 | ✅ |
| v1.4.1 | Correção: Translate e Wikipedia no macOS | ✅ |
| v1.4.2 | Correção: rótulo do botão Sentence; ícone `edit_lookup.svg` | ✅ |
| v1.4.3 | Botões só com ícone (Sentence, Load, Retry) | ✅ |
| v1.4.4 | Correção: botão Sentence quando a seleção já é a frase | ✅ |
| v1.4.5 | Correções da revisão: consultas aninhadas sobrepostas; card oculto | ✅ |
| v1.5.0 | D.3: localização pt_BR/pt_PT; D.4: seletor de cards no título | ✅ |
| v1.6.0+ | Fase 4, um item por versão | ⬜ |

Toda entrega sobe a versão em `main.lua`/`_meta.lua`, no `.md` do plugin (badge e linha de versão) e no `README.md`, e passa no `luacheck` sem avisos.

---

## Fase 0 — Preparação

Pouco esforço; libera as fases seguintes.

| # | Status | Item | Por quê | Versão |
|---|---|---|---|---|
| 0.1 | ✅ | Estado de carregamento comum aos três cards: `não consultado`, `carregando`, `carregado`, `vazio`, `erro` | Distingue "ainda não consultado" de "nenhuma definição encontrada" (1.1) e substitui as flags soltas (`*_loading`, `*_error`, `*_payload`) de Translate e Wikipedia | v1.1.0 |
| 0.2 | ✅ | Limpeza: unificar `schedulePreviewLoad`/`schedulePageLoad`, remover o menu legado "left action", remover o 3º argumento ignorado de `showCarousel` | Menos pontos de alteração nas fases seguintes | v1.1.0 |
| 0.3 | ✅ | Testes de regressão dos patches de `showDict`, `lookupDict`, `translate`, `lookupWikipedia` | As fases 1 e 2 mexem exatamente nesses pontos de entrada | v1.1.0 |

## Fase 1 — Lacunas centrais

Alto valor, esforço baixo a médio: são as diferenças que o usuário sente logo ao trocar o popup nativo pelo carrossel.

| # | Status | Item | Valor | Esforço | Versão |
|---|---|---|---|---|---|
| 1.1 | ✅ | **Dicionário carregado em qualquer ponto de entrada.** Ao abrir o card Dictionary depois de entrar por Translate ou Wikipedia, fazer a consulta local, distinguindo "não consultado" de "sem definição" | ★★★★★ | Médio | v1.1.0 |
| 1.2 | ✅ | **Preservar a rolagem por card e por resultado** (definição 1, definição 2, cada artigo…), válida enquanto a consulta estiver aberta | ★★★★★ | Baixo–médio | v1.1.0 |
| 1.3 | ✅ | **Cache em memória de Translate e Wikipedia** (LRU limitado; chave `serviço\|texto\|origem\|destino` ou `\|idioma`) | ★★★★ | Baixo | v1.2.0 |
| 1.4 | ✅ | **Botão do Vocabulary Builder** no card Dictionary, opcional nas configurações, exibido só quando `ui.vocabbuilder` existir | ★★★★ | Baixo | v1.2.0 |

## Fase 2 — Navegar dentro do preview

Alto valor, esforço médio. Base comum: uma **pilha de consultas** no estado (termo, payloads, rolagem) com botão "voltar" no header. Implementar a pilha uma vez e montar os três itens em cima dela.

| # | Status | Item | Valor | Esforço | Versão |
|---|---|---|---|---|---|
| 2.1 | ✅ | **Links nas definições** (`bword://`, referências cruzadas) abrem a palavra no próprio carrossel | ★★★★ | Baixo (com a pilha) | v1.3.0 |
| 2.2 | ✅ | **Editar o termo consultado** (OCR, pontuação, expressão), mantendo o trecho original separado da consulta | ★★★★ | Médio | v1.3.0 |
| 2.3 | ✅ | **Consulta aninhada**: toque longo numa palavra da definição, tradução ou artigo | ★★★ | Médio | v1.3.0 |

> Regra da fase: Highlight, Note e Search continuam agindo sobre a **seleção original do livro**, nunca sobre o termo editado ou aninhado.

## Fase 3 — Conforto de leitura

Valor médio, esforço baixo a médio.

| # | Status | Item | Valor | Esforço | Versão |
|---|---|---|---|---|---|
| 3.1 | ✅ | **Compacto / Expandido** (alterna a altura do card, mantendo a rolagem) e **tamanho de fonte** configurável | ★★★★ | Médio | v1.4.0 |
| 3.2 | ✅ | **Idioma de origem selecionável** no card Translate | ★★★ | Baixo–médio | v1.4.0 |
| 3.3 | ✅ | **Traduzir a frase** em que a palavra está, usando o contexto da seleção | ★★★ | Baixo–médio | v1.4.0 |
| 3.4 | ✅ | **Escolher quais cards aparecem e em que ordem**, e **lembrar o último card usado** | ★★★ | Médio | v1.4.0 |
| 3.5 | ✅ | **Navegação por teclas físicas** (virar página e setas trocam de card e de resultado) | ★★ | Baixo | v1.4.0 |

## Fase 4 — Estudo e persistência

Valor médio, esforço maior.

| # | Status | Item | Valor | Esforço | Depende de | Versão |
|---|---|---|---|---|---|---|
| 4.1 | ⬜ | **Nota de estudo com contexto**: termo, definição ou tradução, frase original e referência do livro, pelo fluxo de notas existente | ★★★ | Médio | 3.3 | |
| 4.2 | ⬜ | **Histórico recente unificado**, com favoritos e opção de limpar | ★★★ | Médio–alto | 1.3, pilha da fase 2 | |
| 4.3 | ⬜ | **Cache persistente para uso offline**, com indicação de "salvo" e ação Atualizar | ★★ | Médio | 1.3, 4.2 | |
| 4.4 | ⬜ | **Preferências por livro** (idiomas e apresentação) em `doc_settings`, herdando as globais | ★★ | Médio | 3.2, 3.4 | |

Por que a fase 4 fica por último: a 4.1 se sobrepõe em parte ao Vocabulary Builder (1.4), então vale ver como o 1.4 é usado antes de definir o formato da nota. A 4.3 e a 4.4 resolvem casos mais raros e criam dados persistentes que depois precisam ser migrados.

---

## Itens descobertos durante a implementação

Fora do plano original; ainda sem fase definida.

| # | Status | Item | Valor | Esforço | Origem |
|---|---|---|---|---|---|
| D.2 | ✅ | **Trocar o modo dos cards laterais com o carrossel aberto** (`refreshVisibleCards` depois de mudar entre cards inteiros e abas): a linha fica mais alta, mas o popup não recalcula a posição, e o card passa da borda inferior. Já existia antes; na prática quase não acontece, porque o menu de configurações abre com o carrossel fechado | ★ | Baixo | v1.3.0 (screenshot) → feito na v1.4.0 |
| D.3 | ✅ | **Localização pt_BR/pt_PT** no padrão dos outros plugins do repositório (`lookuppreview_l10n.lua`, como `dictionaryexplorer_l10n.lua` e `pageanchor_l10n.lua`): uma tabela com os textos próprios do plugin (menus, ajuda, dicas dos botões, mensagens dos cards), usando o catálogo do KOReader para os termos nativos e para os outros idiomas. Hoje esses textos aparecem em inglês no KOReader em português, porque o catálogo do KOReader não os contém | ★★★★ | Médio | v1.4.2 (pedido do usuário) → feito na v1.5.0 |
| D.4 | ✅ | **Seletor de cards no título.** Tirar o botão ☰ que fica ao lado do ✎ e abrir a lista de cards tocando no título do card, com um indicador visível de que o título é tocável (por exemplo, `Dictionary ▾`, no padrão do subtítulo que já abre listas). Isso libera espaço no header. A definir na implementação: no card Dictionary o título hoje é a palavra consultada, então o nome do card precisa de um lugar próprio (uma linha pequena acima da palavra, ou a palavra passa para o subtítulo); no modo de abas, onde as abas já fazem esse papel, o título talvez nem precise do indicador | ★★★ | Baixo–médio | v1.4.3 (pedido do usuário) → feito na v1.5.0 |
| D.1 | ✅ | **Consultas online canceláveis.** Translate e Wikipedia chamam `Trapper:dismissableRunInSubprocess` fora de `Trapper:wrap`, então rodam bloqueando, no mesmo processo, sem como cancelar com um toque. Envolver em `Trapper:wrap` as torna canceláveis e não trava a interface em rede lenta. Combina com o cache (1.3) | ★★★ | Baixo | v1.1.0 → feito na v1.2.0 |

---

## Registro de entregas

Notas do que foi feito em cada versão, incluindo desvios do plano.

### v1.1.0

**Concluídos:** 0.1, 0.2, 0.3, 1.1, 1.2.

- **0.1** Cada card guarda seu estado em `state.load[card]` (`idle`, `loading`, `done`, `empty`, `error`, com a mensagem). Translate e Wikipedia deixaram de usar `*_loading`/`*_error`. Mudanças visíveis: "No translation found." agora é `empty` e mostra só o botão da janela nativa (antes mostrava Copy e Note, que copiavam a própria mensagem), mantendo no subtítulo o seletor `Origem → Destino ▾` para tentar outro idioma; na Wikipedia, "nenhum artigo" é `empty`, com o botão de idioma e Retry, como antes.
- **0.2** Removidos: o menu legado "left action" (`getLeftButtonAction`/`setLeftButtonAction`/`genLeftButtonActionMenu`/`getLeftButtonSpec`/`runLeftButtonAction`, `SETTING_LEFT_ACTION`, `LEFT_ACTIONS`), `LookupPreview:lookupWikipedia`, `useRawDictionaryHtml`, o alias `showFootnotePreview` (o KOReader não o chama), `loadFullWikipediaArticle`/`pickBestWikipediaPage`/`wikipedia_full_loading` (nunca chamados) e o 3º argumento de `showCarousel`. `schedulePreviewLoad` e `schedulePageLoad` viraram `LookupPreview:scheduleCardLoad`. Os 4 avisos de luacheck que já existiam foram corrigidos.
- **0.3** Desvio: em vez de uma simulação com stand-ins, os testes rodam num **KOReader real sem janela** (`tools/lookuppreview/run.sh check`), como os do Dictionary Explorer, cujo gerador de dicionários reaproveitam. São três suítes (`entry`, `dictionary`, `scroll`) com 84 verificações e gestos reais. Translate e Wikipedia são substituídos por stand-ins, então não usam rede. Validados por mutação: desligar a 1.1 derruba 15 verificações e desligar a 1.2 derruba 9.
- **1.1** Pelo próprio `onLookupWord` do KOReader: o `showDict` resultante é capturado e preenche o card. Busca fuzzy, dicionários do livro e histórico funcionam como numa consulta do livro. O diálogo "No results found" (busca fuzzy) é pulado enquanto o card consulta. O dicionário é consultado sempre, mesmo no modo "Manual only", por ser local. Com consulta em app externo (Android), o card avisa em vez de consultar.
- **1.2** Posição guardada por `card:resultado` (`1:<índice>`, `2:<idioma>`, `3:<idioma>:<artigo>`) a cada rolagem e restaurada antes do primeiro desenho, sem custo de renderização extra. Quando o número de páginas muda (card lateral sem botões, outro modo de HTML), mostra a mesma proporção do conteúdo.
- **Extra:** quando uma consulta termina depois de o usuário trocar de card, o card lateral também é atualizado (antes ficava em "Querying…").
- **Descoberto:** D.1.
- **Corrigido na revisão (P2):** a primeira versão do estado `empty` da tradução perdia o seletor de idioma do subtítulo. Agora o payload vazio sai de `buildTranslationPayload`, e a suíte `dictionary` verifica o seletor e o menu.

### v1.2.0

**Concluídos:** 1.3, 1.4, D.1.

- **1.3** Cache LRU em memória com as 64 respostas mais recentes, guardado no contexto compartilhado do plugin. Por isso sobrevive à troca de livro na mesma sessão do KOReader e é esvaziado ao reiniciar. A chave é `serviço + idioma(s) + texto`; na tradução entra o idioma de origem *pedido* (normalmente `auto`), não o detectado. "Nada encontrado" também é guardado; erros e cancelamentos não. **Retry** sempre consulta de novo, ignorando o cache. Desvio útil: no modo "Manual only", uma resposta que já está no cache aparece assim que o card abre, porque não usa rede; o resto continua esperando **Load**. Para isso, `scheduleCardLoad` passou a chamar os loaders online também no modo manual, e cada loader decide o que fazer.
- **1.4** Botão **Add to vocabulary builder** no card Dictionary, só quando há definição. Usa o evento `WordLookedUp` com `is_manual = true`, como o popup nativo, e com isso o contexto da seleção vai junto. Depois de adicionar, o card mostra uma notificação e o botão vira um ✓; se a palavra já existe, o próprio Vocabulary Builder abre o diálogo "Vocabulary exists". O botão some quando o Vocabulary Builder adiciona tudo sozinho, como no popup nativo. Nova opção: **Content → Show vocabulary builder button** (ligada por padrão). Novo ícone: `icons/vocabulary.svg`, com `plus` do KOReader como fallback. Bug pego pelos testes antes de chegar ao aparelho: o KOReader registra plugins pelo nome da pasta (`ui.vocabbuilder`), não pelo `name` do módulo (`vocabulary_builder`).
- **D.1** Translate e Wikipedia agora rodam dentro de `Trapper:wrap`, como no KOReader nativo: a consulta vai para um subprocesso e um toque a cancela. A Wikipedia cancelada mostra "Wikipedia lookup interrupted." com **Retry**.
- **Testes:** duas suítes novas, `online` (25 verificações) e `vocabulary` (13, no banco real do Vocabulary Builder), totalizando 122. Validadas por mutação: desligar o cache e o `Trapper:wrap` derruba 16 verificações.
- **Observação:** a v1.1.0 não foi commitada antes desta entrega, então as duas versões estão juntas no working tree, que já está em v1.2.0.

### v1.3.0

**Concluídos:** 2.1, 2.2, 2.3.

- **Pilha de consultas.** Cada consulta feita dentro do carrossel é um novo estado com `parent` apontando para a anterior. O estado novo entra no lugar do atual no mesmo popup (`showState`), sem fechar e reabrir a janela. O botão ‹ no header volta ao anterior exatamente como estava: resultado escolhido, rolagem e conteúdo carregado, sem nova consulta. Resultados de dicionário que chegam para um estado da pilha que não está visível são aplicados a ele (`isStateOpen`).
- **2.1** Um link `bword://palavra` (ou só a palavra) numa definição HTML é consultado *só no dicionário da definição* e sem fuzzy, como no popup nativo (`stardictLookup` com aquele dicionário). Links web são ignorados.
- **2.2** Botão de edição (✎) no header do card ativo: abre um `InputDialog` com o texto atual, e **Look up** consulta o texto editado no mesmo card como uma nova entrada na pilha, mantendo o trecho original separado.
- **2.3** Toque longo no texto do card ativo seleciona uma palavra (arrastar seleciona mais), pelo mesmo mecanismo do popup nativo (`HoldStartText`/`HoldPanText`/`HoldReleaseText` repassados ao `HtmlBoxWidget`). Ao soltar, a seleção é consultada: no mesmo card em Dictionary e Wikipedia; a partir do Translate, no Dictionary, porque consultar a tradução de uma palavra da própria tradução não faria sentido.
- **Regra da fase, com desvio:** Highlight e Search agem sobre a seleção do livro em qualquer nível da pilha. Desvio: **Note** e **Add to vocabulary builder** ficam *ocultos* em consultas aninhadas, em vez de agir sobre a seleção original. O Note gravaria na seleção do livro a tradução de outro texto, e o Vocabulary Builder salvaria a frase do livro como contexto de uma palavra que não está nela. Copy continua disponível.
- **Testes:** nova suíte `navigation` (34 verificações, com toque real no link e toque longo real no texto). O total é 156. Validada por mutação: desligar link, toque longo e voltar derruba 9 verificações. O layout do header (‹, ✎, ☰) foi conferido em screenshots do KOReader headless.
- **Descoberto:** D.2.

### v1.4.0

**Concluídos:** 3.1, 3.2, 3.3, 3.4, 3.5, D.2.

- **3.1** Altura: **Appearance → Card height** (Compacto, 38% da tela, padrão; Expandido, 75%). Desvio de forma: em vez de um botão no header, que já tem ‹, ✎ e ☰, a alternância usa os gestos do popup nativo: abrir dois dedos expande, pinçar compacta. Isso vale só para aquela consulta e para as consultas abertas dentro dela. A troca recria o popup na nova altura (`reopenCarousel`), e cada card mantém a mesma proporção do conteúdo à vista. Tamanho do texto: **Appearance → Text size**, de 14 a 24 (padrão 18).
- **3.2** O seletor do subtítulo continua abrindo direto a lista de destinos (o uso mais comum); no topo dela entra **Translate from: … ▸**, um submenu com a configuração do KOReader, a detecção automática e os idiomas comuns. A escolha vale *só para a consulta* (`translation_source_choice`), sem mudar a configuração global, e o subtítulo mostra o idioma escolhido, não o detectado.
- **3.3** Botão **Sentence** no card Translate (na v1.4.0 o rótulo alternava entre Sentence e Selection; ver v1.4.2): traduz a frase em volta da seleção, que aparece logo abaixo da tradução, e volta para a seleção usando o cache. A frase vem do contexto do crengine (`getSelectedWordContext`, 40 palavras de cada lado), cortado em `. ! ? …` e nas formas CJK. Só em livros refluíveis e só na consulta raiz. Abreviações como "Mr." podem cortar a frase antes da hora.
- **3.4** **Content → Cards**: **Show and order cards** usa o `SortWidget` do KOReader para mostrar, ocultar e ordenar, como na lista de dicionários; pelo menos um card fica visível. A ação de um card oculto volta para o KOReader: com Dictionary oculto, o toque longo abre o popup nativo, e o mesmo vale para Translate e Wikipedia. **Open on the last card used** faz o toque longo abrir no card em que o carrossel foi fechado; Translate e Wikipedia escolhidos no menu de seleção continuam abrindo no próprio card. Internamente, todo o carrossel (posições, vizinhos, abas, menu de cards, swipe) passou a seguir a ordem visível em vez de `índice ± 1`.
- **3.5** Teclas: ←/→ (D-pad) trocam de card; os botões de virar página e ↑/↓ rolam o card; Back fecha.
- **D.2** Mudar cards laterais e sombras com o carrossel aberto agora recria o popup (`reopenCarousel`), já posicionado para a nova altura.
- **Testes:** nova suíte `reading` (33 verificações, com abrir e pinçar reais e teclas reais). O total é 189. Validada por mutação: desligar o gesto, a ordem e o botão de frase derruba 10 verificações. Layouts conferidos em screenshots (card expandido; abas reordenadas com um card oculto; frase traduzida).
- **Bug pego pelos testes:** com a origem escolhida, o subtítulo mostrava o idioma que o serviço disse ter detectado.

### v1.4.1

**Correção** de uma regressão da v1.2.0 (D.1): no KOReader para macOS, Translate e Wikipedia falhavam sempre. O log mostrava `subprocess_done: true  stuff_to_read: false`, ou seja, o subprocesso criado pelo `Trapper:wrap` terminava sem devolver nada. No macOS, um processo derivado por `fork` de um app que já iniciou o Cocoa morre no primeiro acesso à rede, porque a resolução de nomes passa por serviços do sistema que não suportam `fork`. O teste headless não reproduzia o problema, porque roda sem janela e sem Cocoa; ali o subprocesso funciona. A correção (`runOnlineQuery`): fora do macOS as consultas continuam no subprocesso (canceláveis); no macOS (`jit.os == "OSX"`) rodam no próprio processo, como até a v1.1.0. A suíte `online` agora cobre os dois modos (192 verificações).

### v1.4.2

- **Correção:** em pt_BR, o botão da 3.3 mostrava "Sentence" e, depois do toque, "Seleção". O catálogo de traduções do KOReader tem "Selection" mas não "Sentence", e como o plugin usa esse catálogo, os dois rótulos saíam em idiomas diferentes. Agora o rótulo é sempre **Sentence** e fica em negrito enquanto a frase está sendo traduzida; a dica do toque longo continua dizendo o que o próximo toque faz, e a frase aparece embaixo da tradução. A suíte `reading` verifica o rótulo e o negrito nos dois estados.
- **Ícone:** o botão de editar usa `icons/edit_lookup.svg` (estilo Material, como os outros ícones do plugin). `edit.svg` continua aceito como alternativa, e o `edit` do KOReader continua como último recurso.
- **Observação para o futuro:** os textos novos do plugin aparecem em inglês em pt_BR, porque o catálogo do KOReader não os traduz. Um rótulo que troca de texto conforme o estado só fica consistente se as duas palavras tiverem a mesma situação no catálogo.

### v1.4.3

- **Botões só com ícone**, com a explicação na dica ao segurar, para ficarem consistentes em qualquer idioma. São ícones Material Symbols fornecidos pelo usuário:
  - **Sentence:** `translate_sentence.svg` (Material `notes`) enquanto a seleção é traduzida, e `translate_selection.svg` (`short_text`) enquanto a frase é traduzida. O ícone mostra o que o toque faz, como o "+" do Vocabulary Builder vira "✓". Isso substitui o negrito da v1.4.2.
  - **Load:** `load_online.svg` (`cloud_download`).
  - **Retry:** `retry.svg` (`refresh`), nos três cards.
  - O texto antigo continua como reserva se o SVG não existir, como nos outros botões. Só o código de idioma da Wikipedia (`EN`, `PT`…) e o contador `1 / 3` continuam como texto, porque não dependem de tradução.
- **Testes:** as suítes `reading`, `online` e `dictionary` verificam o arquivo de ícone de cada um desses botões (198 verificações). Layout conferido em screenshots.
- **Planejado:** D.3, a localização pt_BR/pt_PT, para a v1.5.0; a Fase 4 passa para a v1.6.0+.

### v1.4.4

- **Correção:** o botão Sentence aparecia mesmo quando a seleção já era a frase. A comparação era de texto exato, então bastava a seleção não incluir o ponto final para a "frase" ficar um pouco maior. Agora seleção e frase são comparadas sem pontuação nas pontas (ponto final, aspas), espaços extras e diferença de maiúsculas/minúsculas; se forem iguais, o botão não aparece.
- **Correção encontrada pelo teste:** uma seleção que começa na primeira palavra do texto (o começo de um capítulo) gerava a frase com a primeira letra repetida ("OO livro…"). Sem palavra antes da seleção, o `getSelectedWordContext` do KOReader devolve como contexto anterior o próprio início da seleção. Agora, nesse caso, o contexto anterior fica vazio.
- **Limite do KOReader:** no fim do texto (sem palavra depois da seleção), o contexto seguinte vem vazio e a frase fica sem o ponto final. A tradução não muda.
- **Testes:** a suíte `reading` usa seleções reais do livro: a frase menor que a seleção, o começo do texto, a seleção igual à frase sem o ponto e o fim do texto (202 verificações).
- **Planejado:** D.4 (seletor de cards no título) junto com a D.3 na v1.5.0.

### v1.4.5

Duas correções apontadas em revisão (P2), ambas reproduzidas antes em teste:

- **Consultas aninhadas que se sobrepõem** (regressão da v1.3.0). Havia uma única `dictionary_capture`, e uma segunda consulta feita antes da primeira responder encerrava a captura da primeira. O resultado da primeira chegava ao `showDict` sem dono, seguia o caminho normal e substituía a consulta mostrada, enquanto o estado dela ficava em "loading" para sempre. Agora há uma lista de consultas pendentes (`dictionary_captures`), e cada resultado vai para a consulta da mesma palavra. Além disso, como o `ReaderDictionary` do KOReader não aguenta duas buscas ao mesmo tempo (elas compartilham a mensagem de progresso e o toque que cancela, e a primeira a terminar cancelava a segunda), as buscas passaram a ir para uma **fila**: uma por vez, e a próxima começa no tick seguinte (`startNextDictionaryLookup`). Consultas de cards já fechados são puladas. O diálogo "No results" do KOReader volta quando não há mais nada pendente.
- **Ocultar o card ativo** (regressão da v1.4.0). `reopenCarousel()` trocava o card ativo por um card visível, mas não o carregava. Agora o carregamento é agendado depois da troca (cards já carregados são ignorados).
- **Testes:** `navigation` cobre duas consultas sobrepostas (cada estado com seus resultados, nada extra aberto, nada pendente) e `reading` cobre ocultar o card ativo (o substituto aparece carregado), 209 verificações no total. As verificações antigas de captura foram atualizadas para a lista; com o campo antigo, passariam sempre sem testar nada. Validado por mutação: sem a fila, ou sem o agendamento, as verificações novas falham.

### v1.5.0

**Concluídos:** D.3, D.4.

- **D.4 Seletor de cards no título.** O botão ☰ saiu. O título do card passou a ser o **nome do card com ▾** (`Dictionary ▾`, `Translate ▾`, `Wikipedia ▾`), e tocar nele abre a lista de cards logo abaixo do título, alinhada à esquerda. Decisão sobre o ponto em aberto: no card Dictionary, a palavra **desceu para o subtítulo**, junto com o dicionário (`livro · Nome do dicionário ▾`), e esse subtítulo continua abrindo a lista de resultados. Com isso, os três cards seguem o mesmo esquema: título = card, subtítulo = contexto. Com **abas** não há título (as abas já nomeiam e trocam os cards) e o subtítulo sobe para o lugar dele, como já acontecia no Translate e na Wikipedia. Com **um só card visível**, o título aparece sem ▾ e não abre nada. O `icons/menu.svg` deixou de ser usado.
- **D.3 Localização pt_BR/pt_PT.** `lookuppreview_l10n.lua` no padrão de `dictionaryexplorer_l10n.lua`: uma tabela para os dois portugueses, que usa o catálogo do KOReader para os termos nativos e os outros idiomas. As 165 strings do plugin estão cobertas: 148 na tabela e 17 que o catálogo do KOReader já traduz ("Cancelar", "Destacar", "construtor de vocabulário"…), cuja terminologia foi seguida. Diferença do padrão: o `pgettext` também consulta a tabela, porque o plugin usa `C_("Wikipedia", "Full article")`. O `_meta.lua` também usa a tabela. Correção de texto em inglês: "Show source text" dizia que a origem aparece *acima* da tradução; ela aparece abaixo.
- **Extra (visto no screenshot em pt_BR):** com o KOReader em pt_BR, o idioma de destino vem como `pt_br` e aparecia como "PT_BR". O rótulo agora procura também `pt-BR` e `pt`, e mostra "Português (Brasil)".
- **Testes:** nova suíte `l10n`, que roda com o KOReader em pt_BR: varre o código-fonte e verifica que todo texto passado a `_()`/`C_()` tem tradução e mantém os `%s`/`%d`; confere menu, título e dicas em português e o nome de `pt_br`. A `reading` cobre o título (nome com ▾, lista abaixo do título, sem título com um card ou com abas), e a `scroll` passou a esperar a posição proporcional ao trocar para abas, porque sem título o conteúdo cabe em menos páginas. O `run.sh` aceita `LP_LANGUAGE=pt_BR` para rodar qualquer suíte num idioma. 226 verificações. Validado por mutação: remover uma tradução ou um placeholder derruba a `l10n`.
