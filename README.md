# KOReader Plugins

Este repositório reúne plugins customizados para o [KOReader](https://koreader.rocks/).

Cada plugin fica em sua própria pasta `.koplugin/` e possui um arquivo de documentação específico na raiz do repositório.

## Plugins disponíveis

| Plugin | Pasta | Documentação |
|---|---|---|
| Plain UI Custom | `plainui-custom.koplugin/` | [plainui-custom.koplugin.md](./plainui-custom.koplugin.md) |
| Dictionary Preview | `dictionarypreview.koplugin/` | [dictionarypreview.koplugin.md](./dictionarypreview.koplugin.md) |
| Reader Header Footer | `readerheaderfooter.koplugin/` | [readerheaderfooter.koplugin.md](./readerheaderfooter.koplugin.md) |

Cada pasta `.koplugin/` contém os arquivos necessários para o KOReader carregar o plugin, geralmente incluindo pelo menos:

```text
_meta.lua
main.lua
```

Alguns plugins podem possuir subpastas adicionais, como `modules/` ou `icons/`. Consulte o README específico de cada plugin antes de instalar ou modificar seus arquivos.

## Instalação

1. Baixe ou clone este repositório.
2. Escolha o plugin que deseja instalar.
3. Copie a pasta `.koplugin/` correspondente para o diretório de plugins do KOReader.

Exemplo:

```text
koreader/plugins/nome-do-plugin.koplugin/
```

Em alguns dispositivos, especialmente Kindle, o caminho pode ser semelhante a:

```text
/mnt/us/koreader/plugins/nome-do-plugin.koplugin/
```

4. Reinicie o KOReader.
5. Consulte o README do plugin instalado para saber onde encontrá-lo na interface e como configurá-lo.

## Atualização

Para atualizar um plugin:

1. Feche o KOReader.
2. Substitua a pasta `.koplugin/` antiga pela versão nova.
3. Reinicie o KOReader.

Se o plugin salvar preferências internas, essas configurações normalmente permanecem armazenadas pelo KOReader mesmo após a substituição dos arquivos.

## Remoção

Para remover um plugin:

1. Feche o KOReader.
2. Apague a pasta `.koplugin/` correspondente do diretório de plugins.
3. Reinicie o KOReader.

Exemplo:

```text
koreader/plugins/nome-do-plugin.koplugin/
```

As configurações salvas pelo KOReader podem permanecer no armazenamento interno, mas deixam de ter efeito quando o plugin não está mais instalado.

## Compatibilidade

Estes plugins foram criados para uso com versões recentes do KOReader e podem depender de APIs internas do aplicativo. Como o KOReader está em desenvolvimento ativo, atualizações futuras podem exigir ajustes nos plugins.

Caso algum plugin deixe de carregar após uma atualização do KOReader, verifique primeiro o README específico dele e os logs do KOReader.

## Desenvolvimento

Para adicionar um novo plugin ao repositório, recomenda-se manter o mesmo padrão:

```text
novo-plugin.koplugin/
├── _meta.lua
└── main.lua

novo-plugin.koplugin.md
```

O arquivo `.md` na raiz deve explicar o funcionamento, instalação, opções de configuração e limitações específicas do plugin.

## Licença

Consulte os cabeçalhos dos arquivos e a documentação específica de cada plugin para informações de licença e créditos.
