# Claude Statusline Customizer

Este projeto contém um script customizado para a `statusLine` do Claude CLI, fornecendo informações em tempo real sobre a sessão, uso de modelos, custos e limites de taxa de forma visual e organizada.

## 🚀 Como Funciona

O script `statusline-command.sh` é executado pelo Claude CLI a cada interação. Ele funciona da seguinte forma:

1. **Captura de Dados:** Recebe um JSON contendo o estado atual da sessão via `stdin`.
2. **Snapshot de Depuração:** Salva o JSON recebido em `last_input.json` para permitir inspeção manual dos dados brutos (tokens, custos exatos, etc).
3. **Processamento:** Extrai os campos necessários usando `jq` (ou `python` como fallback).
4. **Estatísticas Persistentes:** Lê o arquivo `stats-cache.json` para recuperar o histórico de mensagens do dia.
5. **Saída Visual:** Imprime uma linha única formatada com cores ANSI para o terminal.

## 📂 Estrutura de Arquivos

- `statusline-command.sh`: O "motor" que processa os dados e gera a barra de status.
- `last_input.json`: Snapshot da última interação. Útil para verificar como o Claude CLI reporta tokens de cache e limites de taxa.
- `stats-cache.json`: Banco de dados local (JSON) que armazena:
    - `dailyActivity`: Contagem de mensagens, sessões e chamadas de ferramentas (`toolCallCount`) por dia.
    - `dailyModelTokens`: Distribuição de uso de tokens por modelo específico.
    - `modelUsage`: Métricas acumulativas de tokens de entrada, saída e **cache** (read/creation).

## ✨ Funcionalidades

- **Identificação do Modelo:** Exibe o nome do modelo de forma compacta (remove o prefixo "Claude" e sufixos de data).
- **Integração com Git:** Mostra a branch atual se você estiver dentro de um repositório Git.
- **Monitoramento de Contexto:** Uma barra de progresso visual (0-100%) com cores dinâmicas (Verde < 70%, Amarelo < 90%, Vermelho >= 90%).
- **Contagem de Tokens:** Exibe os tokens de entrada do prompt atual (formatados em 'k').
- **Estatísticas Diárias:** Mostra quantas mensagens foram enviadas hoje com base no `stats-cache.json`.
- **Limites de Taxa (Rate Limits):** Alertas visuais para o uso das cotas de 5 horas e 7 dias.
- **Rastreamento de Custo:** Exibe o custo total acumulado da sessão em USD com precisão de 4 casas decimais.

## 🛠️ Instalação

Para instalar e ativar esta statusline, siga os passos abaixo:

1. Certifique-se de que o script está na pasta correta: `~/.claude/statusline/statusline-command.sh`.
2. Dê permissão de execução ao script:
   ```bash
   chmod +x ~/.claude/statusline/statusline-command.sh
   ```
3. Edite o seu arquivo de configurações do Claude CLI (geralmente em `~/.claude/settings.json`) e adicione/altere a seção `statusLine`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /c/Users/aless/.claude/statusline/statusline-command.sh"
  }
}
```

*Nota: O caminho pode variar dependendo do seu sistema operacional (no Windows/Git Bash use o caminho estilo Unix como no exemplo acima).*

## 📝 Legenda da Statusline

A saída segue este padrão visual:
`Modelo [branch] | ctx: 25% [###-------]/200k | msgs: 15 | Limits(5h:10% | 7d:5%) | prompt: 1.2k | $0.0045`

| Campo | Descrição | Cores |
| :--- | :--- | :--- |
| **Modelo** | Nome abreviado do modelo em uso. | Ciano |
| **[branch]** | Branch Git atual (se disponível). | Azul |
| **ctx: X%** | Percentual de uso da janela de contexto. | Verde/Amarelo/Vermelho |
| **[###---]** | Barra visual de uso do contexto. | Colorida conforme o % |
| **200k** | Tamanho total da janela de contexto. | Vermelho |
| **msgs** | Total de mensagens enviadas hoje. | Ciano |
| **5h / 7d** | Uso das cotas de rate limit. | Ciano (baixo) / Amarelo (médio) / Vermelho (alto) |
| **prompt** | Tokens de entrada no último prompt. | Branco |
| **$0.0000** | Custo total da sessão em dólares. | Amarelo |

## 📦 Dependências

- **Bash:** Ambiente de execução.
- **jq (Recomendado):** Para processamento rápido de JSON.
- **Python (Fallback):** Caso o `jq` não esteja instalado, o script utiliza Python para processar os dados.
- **Git:** Necessário para exibir informações de branch.
