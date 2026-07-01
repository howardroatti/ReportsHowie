# Screenshots do manual

O manual HTML (`docs/index.html`) referencia as imagens abaixo. Enquanto um arquivo não existir, o manual mostra um **placeholder** com a descrição do que capturar (o `<figure>` some sozinho quando a imagem carrega).

Coloque os PNGs aqui com estes nomes:

| Arquivo | O que capturar |
|---|---|
| `designer.png` | O designer aberto (duplo-clique no `TrhReport`): ribbon no topo, painel **Dados** à esquerda, superfície central com bandas, inspetor à direita. |
| `painel-dados.png` | Recorte do painel **Dados** (árvore `dataset → campos`). |
| `preview-embutida.png` | Um form com o `TrhPreviewControl` embutido mostrando um relatório, com a barra de navegação/zoom. |
| `relatorio-aninhado.png` | O preview do relatório hierárquico **Cliente › Categoria › Produtos** com subtotais por categoria e total do cliente. |

Sugestões: PNG, largura ~1000–1400px, sem informações sensíveis (dados reais/senhas). Depois de adicionar, é só abrir `docs/index.html` — as imagens substituem os placeholders automaticamente.
