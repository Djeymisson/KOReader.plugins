# Plain UI Custom

**Plain UI Custom** é um plugin para o [KOReader](https://github.com/koreader/koreader) que modifica a tela do gerenciador de arquivos para oferecer uma navegação mais orientada à biblioteca, com abas para **Files**, **Series**, **Authors** e **Tags**, além de filtros, ordenação por visualização e anotações visuais em capas/listagens.

O plugin funciona como uma camada de personalização sobre o File Manager do KOReader. Ele cria visualizações virtuais a partir dos metadados dos livros e adapta a interface para facilitar a navegação por autor, série e tag sem mover ou renomear arquivos no armazenamento.

## Funcionalidades

- Adiciona abas de navegação no gerenciador de arquivos:
  - **Files**
  - **Series**
  - **Authors**
  - **Tags**
- Cria caminhos virtuais para navegar por metadados.
- Permite listar livros por:
  - autor;
  - série;
  - tag/palavra-chave.
- Suporta filtros por status de leitura:
  - todos;
  - não lidos;
  - em leitura;
  - finalizados.
- Adiciona menus de filtro e ordenação por aba.
- Permite refinar a visualização por múltiplos metadados usando um menu de facetas.
- Mantém a navegação baseada no diretório real da biblioteca, mas adiciona uma camada virtual de organização.
- Personaliza cabeçalho e rodapé do File Manager.
- Exibe informações de status no cabeçalho/rodapé, como Wi-Fi, bateria e horário, dependendo da configuração dos módulos.
- Integra anotações visuais de capa/listagem, como porcentagem de leitura e indicação de livro finalizado, quando os módulos correspondentes estão presentes.

## Estrutura recomendada

A pasta do plugin deve ficar assim:

```text
plainui-custom.koplugin/
├── _meta.lua
├── main.lua
└── modules/
    ├── author_series.lua
    ├── metadata_tabs.lua
    ├── metadata_facet_dropdown.lua
    ├── metadata_source.lua
    ├── metadata_sort.lua
    ├── filter_state.lua
    ├── virtual_path.lua
    ├── virtual_leaf.lua
    ├── tab_option_dialog.lua
    ├── tab_option_presenter.lua
    ├── tab_view_options.lua
    ├── status_indicators.lua
    ├── cover_badge.lua
    ├── cover_overlay.lua
    ├── finished_badge.lua
    └── reading_percentage.lua
```

Alguns desses módulos são dependências internas usadas pelos arquivos principais. Se algum módulo estiver ausente, o KOReader pode falhar ao carregar o plugin durante a inicialização.

## Instalação

1. Baixe ou clone este repositório.
2. Copie a pasta do plugin para a pasta `plugins` do KOReader.

Exemplo:

```text
koreader/plugins/plainui-custom.koplugin/
```

Em dispositivos Kindle, a estrutura geralmente fica em algo como:

```text
/KOReader/plugins/plainui-custom.koplugin/
```

3. Reinicie o KOReader.
4. Abra o gerenciador de arquivos.

O plugin é carregado automaticamente ao iniciar o KOReader. Ele não é limitado ao leitor de documentos, pois atua principalmente sobre o File Manager.

## Como usar

Após instalar e reiniciar o KOReader, abra o gerenciador de arquivos. A interface passa a mostrar abas de navegação para acessar os livros por arquivos, séries, autores e tags.

### Abas principais

- **Files** mostra a navegação tradicional por pastas e arquivos.
- **Series** agrupa os livros por série.
- **Authors** agrupa os livros por autor.
- **Tags** agrupa os livros por tags/metadados de palavra-chave.

Ao tocar em uma aba que não está selecionada, o plugin muda a visualização. Ao tocar novamente na aba selecionada, o plugin abre o menu de opções daquela visualização.

### Filtros e ordenação

Cada aba pode ter opções próprias de filtro e ordenação. O menu de opções permite alternar entre diferentes filtros de status e modos de ordenação.

Exemplos de filtros:

```text
All
Unread
Reading
Finished
```

Dependendo da aba, a ordenação pode ser feita por nome, título, autor, série, progresso ou acesso recente.

### Navegação por metadados

Ao entrar em uma visualização por autor, série ou tag, o plugin cria uma lista virtual de valores de metadados. Ao selecionar um valor, o File Manager mostra os livros correspondentes.

Esses caminhos são virtuais: eles servem apenas para navegação dentro do KOReader e não representam pastas reais no sistema de arquivos.

### Refinamento por facetas

Quando você está dentro de um grupo de metadados, o plugin pode exibir um menu de facetas para refinar a lista atual. Isso permite combinar filtros, por exemplo:

```text
Autor → Série
Tag → Autor
Série → Status de leitura
```

O menu também mostra contagens quando disponíveis, ajudando a entender quantos livros restam em cada opção.

## Como funciona internamente

O plugin é composto por módulos que aplicam patches em partes do KOReader.

### `_meta.lua`

Define os metadados do plugin:

```lua
name = "plainui-custom"
fullname = "Plain UI Custom"
version = "1.2-custom"
```

Essas informações são usadas pelo KOReader para identificar o plugin.

### `main.lua`

É o ponto de entrada do plugin. Ele aplica os patches uma única vez e carrega os módulos principais:

```lua
modules.author_series
modules.metadata_tabs
modules.finished_badge
modules.reading_percentage
```

### `modules/author_series.lua`

Adiciona a navegação virtual por metadados ao File Manager. Esse módulo altera partes do `FileManager` e do `FileChooser` para reconhecer caminhos virtuais, gerar listas de autores/séries/tags e exibir os livros correspondentes.

Ele também registra ações como:

```text
Browse by author
Browse by series
Browse by tag
```

### `modules/metadata_tabs.lua`

Modifica a interface do File Manager. Esse módulo adiciona a barra de abas, adapta o cabeçalho/rodapé, atualiza o estado visual da aba selecionada e integra os menus de filtro e ordenação.

Também gerencia informações de contexto, como:

- pasta atual;
- visualização atual;
- filtro aplicado;
- grupo de metadados aberto;
- indicadores de status.

### `modules/metadata_facet_dropdown.lua`

Mostra menus de refinamento por facetas. Ele permite navegar entre dimensões de metadados e escolher filtros adicionais sem sair da visualização atual.

### `modules/metadata_source.lua`

Centraliza o acesso aos metadados dos livros. Esse módulo consulta o banco de informações do KOReader, filtra arquivos válidos, calcula contagens e mantém caches para melhorar o desempenho em bibliotecas grandes.

Ele considera como livros arquivos com extensões como:

```text
azw, cbr, cbt, cbz, djvu, epub, fb2, mobi, pdf, rtf
```

## Personalização

Alguns ajustes visuais podem ser feitos diretamente nos módulos.

Em `modules/metadata_tabs.lua`, procure constantes como:

```lua
local PLAINUI_TABS_AT_BOTTOM = true
local PLAINUI_BOTTOM_FONT_SIZE = 22
local PLAINUI_HEADER_FOLDER_FONT_SIZE = 22
local PLAINUI_SIDE_MARGIN = Screen:scaleBySize(14)
```

Essas opções controlam, por exemplo:

- se as abas ficam no rodapé;
- tamanho da fonte no rodapé;
- tamanho da fonte do contexto no cabeçalho;
- margem lateral da interface.

Após alterar esses valores, reinicie o KOReader para aplicar as mudanças.

## Observações importantes

- O plugin modifica o comportamento interno do File Manager por meio de patches. Mudanças futuras no KOReader podem exigir ajustes no plugin.
- A navegação por metadados depende dos metadados conhecidos pelo KOReader. Livros ainda não indexados ou sem metadados podem aparecer de forma incompleta.
- A primeira navegação em bibliotecas grandes pode ser mais lenta, pois o plugin precisa montar listas e caches.
- Os caminhos virtuais são apenas uma representação dentro do KOReader. Nenhum arquivo é movido, renomeado ou reorganizado no armazenamento.
- Se a listagem parecer desatualizada, use a opção de atualizar/recarregar a pasta no KOReader para invalidar caches e reconstruir a visualização.
- Os módulos `finished_badge.lua` e `reading_percentage.lua` precisam estar presentes para que as anotações visuais de capa/listagem sejam aplicadas.

## Compatibilidade

Este plugin foi pensado para versões recentes do KOReader com suporte ao sistema de plugins `.koplugin` e ao File Manager padrão. Como ele aplica patches em classes internas, recomenda-se testar após atualizações grandes do KOReader.

## Créditos

Baseado no trabalho de **Anh Do** e em ideias/adaptações relacionadas ao patch Browse by Metadata, inspirado por contribuições anteriores da comunidade KOReader.

## Licença

MIT, conforme indicado nos cabeçalhos dos módulos.
