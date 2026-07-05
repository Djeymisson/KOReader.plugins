# Selection Toolbar

**Versão:** `v1.0.0`

Plugin para KOReader que substitui o menu centralizado de seleção de texto por uma barra compacta, exibida próxima ao texto selecionado.

## O que faz

Ao selecionar um trecho com mais de uma palavra, o plugin intercepta o menu padrão de highlight e mostra uma única linha de botões com ícones. A barra tenta aparecer abaixo da seleção quando há espaço; caso contrário, aparece acima.

Ações disponíveis:

- Select
- Highlight
- Copy
- Add note
- Wikipedia
- Dictionary
- Translate
- View HTML
- Generate QR code
- Search

As ações nativas reutilizam os callbacks originais do `ReaderHighlight`, preservando o comportamento padrão do KOReader. A ação `Generate QR code` usa o widget nativo `ui/widget/qrmessage`, quando disponível na versão instalada do KOReader.

## Configuração

No leitor, abra:

`Menu superior > Settings > Selection toolbar`

Opções:

- `Use compact selection toolbar`: ativa/desativa a substituição do menu padrão.
- `Version: v1.0.0`: mostra a versão instalada do plugin.
- `Visible actions`: permite escolher quais ações aparecem na barra.
  - `Show all actions`: restaura todas as ações.
  - Demais itens: ativam/desativam individualmente cada ação da barra.

## Ícones

Os ícones ficam em:

`selectiontoolbar.koplugin/icons/`

A versão atual carrega os ícones diretamente da pasta do próprio plugin. Não é necessário copiar SVGs para diretórios internos ou para o diretório de dados do KOReader.

Internamente, o plugin aplica um patch leve no `IconWidget` para aceitar caminhos diretos de arquivos `.svg`/`.png` passados no campo `icon`. Esse patch usa apenas valores definidos explicitamente no widget, evitando conflito com outros plugins que também usam `IconWidget` ou que carregam ícones por `file`.

## Organização e desempenho

A versão `v1.0.0` inclui alguns ajustes internos para reduzir trabalho repetido durante a abertura da toolbar:

- cache dos caminhos dos ícones;
- cache do módulo `ui/widget/qrmessage` após a primeira verificação;
- leitura única das ações visíveis ao montar a barra;
- cálculo do offset da página uma única vez antes de percorrer as caixas da seleção;
- métricas dos botões centralizadas em uma função comum, incluindo largura, altura, tamanho do ícone e padding lateral.

## Instalação

Copie a pasta `selectiontoolbar.koplugin` para a pasta `plugins` do KOReader:

```text
koreader/plugins/selectiontoolbar.koplugin
```

Depois reinicie o KOReader.

## Observações

- `View HTML` só aparece quando a ação original existe no documento atual, seguindo a própria regra do KOReader.
- Em telas muito estreitas, a linha ainda é mantida compacta, mas pode ocupar boa parte da largura disponível se todas as 10 ações estiverem ativas.
- O plugin é reversível: ao desativar a opção `Use compact selection toolbar`, o menu original volta a ser usado.
- Ao fechar o plugin, o patch aplicado no menu de highlight e no `IconWidget` é restaurado quando ainda for o patch ativo do Selection Toolbar.
