# Lookup Preview — Roadmap

Plano de evolução do [Lookup Preview](./lookuppreview.koplugin.md), ordenado pelo valor percebido de cada mudança. Este arquivo é atualizado a cada entrega: marque o item, preencha a versão e anote o que mudou em relação ao planejado.

**Legenda:** ⬜ pendente · 🟨 em andamento · ✅ concluído · ⏸️ adiado · ❌ descartado
**Valor:** ★ (baixo) a ★★★★★ (alto) · **Esforço:** Baixo / Médio / Alto

Versão atual: **v1.1.0**

## Entregas

| Versão | Conteúdo | Status |
|---|---|---|
| v1.1.0 | Fase 0 + 1.1 + 1.2 | ✅ |
| v1.2.0 | 1.3 + 1.4 | ⬜ |
| v1.3.0 | Fase 2 | ⬜ |
| v1.4.0 | Fase 3 | ⬜ |
| v1.5.0+ | Fase 4, um item por versão | ⬜ |

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
| 1.3 | ⬜ | **Cache em memória de Translate e Wikipedia** (LRU limitado; chave `serviço\|texto\|origem\|destino` ou `\|idioma`) | ★★★★ | Baixo | |
| 1.4 | ⬜ | **Botão do Vocabulary Builder** no card Dictionary, opcional nas configurações, exibido só quando `ui.vocabbuilder` existir | ★★★★ | Baixo | |

## Fase 2 — Navegar dentro do preview

Alto valor, esforço médio. Base comum: uma **pilha de consultas** no estado (termo, payloads, rolagem) com botão "voltar" no header. Implementar a pilha uma vez e montar os três itens em cima dela.

| # | Status | Item | Valor | Esforço | Versão |
|---|---|---|---|---|---|
| 2.1 | ⬜ | **Links nas definições** (`bword://`, referências cruzadas) abrem a palavra no próprio carrossel | ★★★★ | Baixo (com a pilha) | |
| 2.2 | ⬜ | **Editar o termo consultado** (OCR, pontuação, expressão), mantendo o trecho original separado da consulta | ★★★★ | Médio | |
| 2.3 | ⬜ | **Consulta aninhada**: toque longo numa palavra da definição, tradução ou artigo | ★★★ | Médio | |

> Regra da fase: Highlight, Note e Search continuam agindo sobre a **seleção original do livro**, nunca sobre o termo editado ou aninhado.

## Fase 3 — Conforto de leitura

Valor médio, esforço baixo a médio.

| # | Status | Item | Valor | Esforço | Versão |
|---|---|---|---|---|---|
| 3.1 | ⬜ | **Compacto / Expandido** (alterna a altura do card, mantendo a rolagem) e **tamanho de fonte** configurável | ★★★★ | Médio | |
| 3.2 | ⬜ | **Idioma de origem selecionável** no card Translate | ★★★ | Baixo–médio | |
| 3.3 | ⬜ | **Traduzir a frase** em que a palavra está, usando o contexto da seleção | ★★★ | Baixo–médio | |
| 3.4 | ⬜ | **Escolher quais cards aparecem e em que ordem**, e **lembrar o último card usado** | ★★★ | Médio | |
| 3.5 | ⬜ | **Navegação por teclas físicas** (virar página e setas trocam de card e de resultado) | ★★ | Baixo | |

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
| D.1 | ⬜ | **Consultas online canceláveis.** Translate e Wikipedia chamam `Trapper:dismissableRunInSubprocess` fora de `Trapper:wrap`, então rodam bloqueando, no mesmo processo, sem como cancelar com um toque. Envolver em `Trapper:wrap` as torna canceláveis e não trava a interface em rede lenta. Combina com o cache (1.3) | ★★★ | Baixo | v1.1.0 |

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
