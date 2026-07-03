# Reader Header Footer

Plugin para o [KOReader](https://koreader.rocks/) que adiciona informações discretas no cabeçalho e no rodapé das páginas durante a leitura.

Ele exibe indicadores diretamente nas margens do documento, sem abrir barras extras ou alterar a interface principal do leitor.

## Funcionalidades

O plugin adiciona quatro áreas de informação à tela de leitura:

- **Topo esquerdo**: título do capítulo ou autor + título do livro.
- **Topo direito**: indicador de Wi-Fi, horário e bateria.
- **Rodapé esquerdo**: páginas restantes no capítulo ou no livro.
- **Rodapé direito**: porcentagem de leitura do documento.

O objetivo é manter informações úteis sempre visíveis, mas de forma leve e pouco intrusiva.

## Como funciona

O plugin é carregado como um módulo do leitor do KOReader e desenha os textos diretamente sobre as regiões superior e inferior da página.

Ele evita redesenhos completos da tela sempre que possível. Em vez disso, invalida apenas as pequenas áreas onde os indicadores aparecem. Isso reduz flickering e evita atualizações pesadas da página inteira.

Também há uma proteção para menus e diálogos: se algum menu do KOReader estiver aberto, a atualização dos indicadores é adiada até que o leitor volte a ser a janela ativa.

## Informações exibidas

### Topo direito

Mostra:

```text
Wi-Fi • HH:MM • Bateria
```

Exemplo:

```text
 • 14:32 •  87%
```

Se o dispositivo não possuir bateria, ou se a informação não estiver disponível, a bateria é omitida.

### Topo esquerdo

Mostra informações contextuais do livro:

- em páginas pares: `Autor • Título`;
- em páginas ímpares: título do capítulo atual;
- no início de um capítulo: o topo esquerdo fica vazio, evitando repetição desnecessária.

### Rodapé esquerdo

Pode exibir uma das duas informações:

```text
10 pages left in chapter
```

ou:

```text
120 pages left in book
```

Esse comportamento é configurável pelo menu do plugin.

### Rodapé direito

Mostra a porcentagem lida do documento:

```text
42%
```

## Instalação

1. Crie uma pasta chamada:

```text
reader_header_footer.koplugin
```

2. Copie os arquivos do plugin para dentro dela:

```text
reader_header_footer.koplugin/
├── _meta.lua
└── main.lua
```

3. Copie a pasta para o diretório de plugins do KOReader.

Em muitos dispositivos, o caminho será semelhante a:

```text
koreader/plugins/reader_header_footer.koplugin
```

Em dispositivos Kindle, normalmente fica em:

```text
/mnt/us/koreader/plugins/reader_header_footer.koplugin
```

4. Reinicie o KOReader.

5. Abra um livro e acesse o menu do leitor para configurar o plugin.

## Configuração

O plugin adiciona um item ao menu principal do leitor:

```text
Header/footer indicators
```

Nesse menu é possível configurar:

### Ativar ou desativar

Permite ligar ou desligar os indicadores sem remover o plugin.

### Informação do rodapé esquerdo

Alterna entre:

- páginas restantes no capítulo;
- páginas restantes no livro.

### Fonte

Permite alterar o tamanho da fonte dos indicadores.

Valores suportados:

```text
mínimo: 10
padrão: 16
máximo: 28
```

Também há uma opção para restaurar o tamanho padrão.

### Margens

Por padrão, o plugin tenta seguir as margens reais do documento, alinhando os indicadores com a área de leitura.

Também é possível desativar esse comportamento e definir margens manuais:

- margem esquerda;
- margem direita;
- margem lateral comum para os dois lados.

Valores suportados:

```text
mínimo: 0
máximo: 300
```

## Configurações salvas

As preferências são armazenadas nas configurações do KOReader usando as seguintes chaves:

```text
reader_header_footer_enabled
reader_header_footer_font_size
reader_header_footer_follow_document_margins
reader_header_footer_custom_left_margin
reader_header_footer_custom_right_margin
reader_header_footer_custom_horizontal_margin
reader_header_footer_left_footer_mode
```

## Atualizações automáticas

O plugin atualiza automaticamente os indicadores nos seguintes eventos:

- mudança de página;
- atualização de posição de leitura;
- mudança no estado do Wi-Fi;
- mudança no carregamento da bateria;
- retomada do dispositivo após suspensão;
- virada de minuto, para atualizar o horário.

A bateria é verificada periodicamente a cada 5 minutos.

## Desempenho

O plugin foi pensado para ser leve. Algumas decisões importantes:

- usa atualização regional em vez de refresh completo;
- evita redesenhar enquanto menus ou diálogos estão abertos;
- atualiza o relógio apenas na virada do minuto;
- verifica bateria em intervalo periódico, não continuamente;
- reaproveita o estado atual de página, contagem de páginas e área visível do leitor.

## Personalização avançada

Alguns valores podem ser ajustados diretamente no início do `main.lua`.

### Tamanho da fonte

```lua
local FONT = {
    name = "NotoSans-Regular.ttf",
    default_size = 16,
    min_size = 10,
    max_size = 28,
}
```

### Espaçamento e posicionamento

```lua
local LAYOUT = {
    padding = 10,
    top_padding = 2,
    bottom_padding = 10,
    text_clear_extra = 6,
    line_extra_for_region = 8,
    line_extra_for_paint = 4,
    left_right_gap = 16,
}
```

### Margens padrão

```lua
local INDICATOR_MARGINS = {
    default_follow_document = true,
    default_left = 20,
    default_right = 20,
    min = 0,
    max = 300,
}
```

## Limitações conhecidas

- O plugin depende das informações de metadados e sumário disponibilizadas pelo KOReader.
- Em documentos sem sumário, a contagem de páginas restantes no capítulo pode cair para a contagem restante no livro.
- O título de capítulo pode ficar vazio se o documento não fornecer uma estrutura de TOC confiável.
- Em layouts muito incomuns, as margens automáticas podem não corresponder exatamente à área visual do texto. Nesses casos, use margens manuais.

## Estrutura do plugin

```text
reader_header_footer.koplugin/
├── _meta.lua   # metadados exibidos pelo KOReader
└── main.lua    # implementação principal do plugin
```

## Créditos

Plugin customizado para KOReader.

