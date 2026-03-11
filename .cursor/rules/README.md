# Cursor Rules - Guia de Uso

Este diretório contém as regras do Cursor para manter a consistência e qualidade do código. As regras estão organizadas em **genéricas** (reutilizáveis) e **específicas do projeto**.

## 📁 Estrutura dos Arquivos

```
.cursor/rules/
├── README.md                 # Este arquivo
├── rules_index.mdc          # Índice completo das regras
│
├── 🔄 REGRAS GENÉRICAS (Reutilizáveis)
│   ├── general_rules.mdc        # Regras gerais e princípios fundamentais
│   ├── clean_architecture.mdc   # Regras genéricas de Clean Architecture (camadas/dependências)
│   ├── solid_principles.mdc     # Princípios SOLID
│   ├── coding_style.mdc         # Guia de estilo Dart 2026
│   ├── null_safety.mdc          # Boas práticas de null safety
│   ├── testing.mdc              # Padrões de testes
│   ├── flutter_widgets.mdc      # Widgets Flutter (estrutura/performance/layout/tokens)
│   └── ui_ux_design.mdc         # Princípios de UI/UX para desktop
│
└── 🎯 REGRAS ESPECÍFICAS
    └── project_specifics.mdc    # Regras específicas deste projeto
```

## 🔄 Copiando Regras para Outros Projetos

### 1. Regras Genéricas (Copie TUDO)

Essas regras são **100% reutilizáveis** em qualquer projeto Flutter/Dart:

✅ **Copie estes arquivos sem modificações:**
- `rules_index.mdc`
- `general_rules.mdc`
- `clean_architecture.mdc`
- `solid_principles.mdc`
- `coding_style.mdc`
- `null_safety.mdc`
- `testing.mdc`
- `flutter_widgets.mdc`
- `ui_ux_design.mdc` (se for app desktop)

### 2. Regras Específicas (Adapte)

Este arquivo precisa ser **adaptado** para cada projeto:

⚠️ **Adapte este arquivo:**
- `project_specifics.mdc` - Ajuste para seu projeto

### Como Adaptar `project_specifics.mdc`

Abra o arquivo e modifique:

1. **Project Type**: Tipo do seu projeto (Desktop App, Mobile App, Web App)
2. **Architecture**: Arquitetura usada (Clean Architecture, MVVM, Simple, etc.)
3. **Project Dependencies**: Dependências específicas do seu projeto
4. **Project Structure**: Estrutura de pastas
5. **Entry Point Pattern**: Padrão de inicialização
6. **Data Flow**: Fluxo de dados específico
7. **Patterns Used**: Padrões usados no projeto

## 📋 Exemplo de Uso

### Para um novo projeto com Clean Architecture:

```bash
# 1. Copie todos os arquivos genéricos
cp -r .cursor/rules/*.mdc /seu-novo-projeto/.cursor/rules/

# 2. Edite apenas project_specifics.mdc
# Ajuste: arquitetura, dependências, estrutura
```

### Para um novo projeto com arquitetura simples:

```bash
# 1. Copie todos os arquivos genéricos
cp -r .cursor/rules/*.mdc /seu-novo-projeto/.cursor/rules/

# 2. Simplifique project_specifics.mdc
# Remova: regras de Clean Architecture, camadas complexas
# Mantenha: dependências, padrões simples
```

## ✨ Conteúdo das Regras Genéricas

### `general_rules.mdc`
- Princípios fundamentais (código conciso, composição, naming)
- Regras de documentação (não criar docs automáticos)
- Código autoexplicativo
- Evitar números mágicos
- Priorizar componentes reutilizáveis

### `solid_principles.mdc`
- Single Responsibility Principle (SRP)
- Open/Closed Principle (OCP)
- Liskov Substitution Principle (LSP)
- Interface Segregation Principle (ISP)
- Dependency Inversion Principle (DIP)
- Exemplos e violações comuns

### `coding_style.mdc`
- Convenções de nomenclatura (2026)
- Declaração de tipos
- Const constructors
- Arrow syntax e expression bodies
- Trailing commas
- Import organization
- Funções e métodos (< 20 linhas)
- Recursos modernos do Dart 3+ (Pattern matching, Records, Switch expressions)

### `null_safety.mdc`
- Nullable vs non-nullable
- Null-aware operators (`?.`, `??`, `??=`)
- Inicialização de variáveis
- Null checks
- APIs externas

### `testing.mdc`
- Estrutura de testes (Unit, Widget)
- AAA pattern (Arrange, Act, Assert)
- Nomenclatura de testes
- Mocking e isolamento
- package:checks para assertions

### `flutter_widgets.mdc`
- Stateless vs Stateful
- Widget composition (private classes, not methods)
- Performance (const, ListView.builder, RepaintBoundary)
- Material 3 theming
- Layout e responsividade
- Tear-offs para widgets

### `ui_ux_design.mdc`
- Hierarquia visual
- Color palette (60-30-10 rule)
- Typography
- Navegação desktop
- Feedback mechanisms
- Accessibility (WCAG 2.1 AA)
- Responsive design
- Keyboard navigation

## 🎯 Ajustando Globs

Se sua estrutura de pastas for diferente, ajuste os `globs` no frontmatter:

```yaml
---
description: Descrição da regra
globs: ["seu_path/**/*.dart"]  # Ajuste aqui
alwaysApply: true
---
```

**Exemplos de ajustes:**

```yaml
# Se usar lib/screens/ ao invés de lib/pages/
globs: ["lib/screens/**/*.dart", "lib/widgets/**/*.dart"]

# Se usar lib/features/ ao invés de lib/presentation/
globs: ["lib/features/**/*.dart"]

# Se usar lib/modules/
globs: ["lib/modules/**/*.dart"]
```

## 📚 Referências

- [Cursor Documentation on Rules](https://docs.cursor.com/en/context/rules)
- [Flutter AI Rules](https://docs.flutter.dev/ai/ai-rules)
- [Effective Dart: Style Guide](https://dart.dev/effective-dart/style)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)
- [Material 3 Guidelines](https://m3.material.io/)

## 🔍 Verificação Rápida

Após copiar as regras para um novo projeto:

- [ ] Todos os arquivos `.mdc` genéricos foram copiados
- [ ] `project_specifics.mdc` foi adaptado para o novo projeto
- [ ] Globs foram ajustados se necessário
- [ ] Arquitetura está corretamente documentada
- [ ] Dependências estão listadas
- [ ] Estrutura de pastas está documentada

## 💡 Dicas

1. **Mantenha as regras genéricas sem modificações** - elas são baseadas em best practices
2. **Adapte apenas project_specifics.mdc** - cada projeto é único
3. **Revise rules_index.mdc** periodicamente - mantenha atualizado
4. **Teste as regras** - o Cursor aplicará automaticamente ao trabalhar nos arquivos
5. **Compartilhe conhecimento** - use estas regras como referência para o time

## 🚀 Quick Start para Novo Projeto

```bash
# 1. Crie a pasta de regras
mkdir -p /seu-projeto/.cursor/rules

# 2. Copie os arquivos genéricos
cp general_rules.mdc solid_principles.mdc coding_style.mdc \
   null_safety.mdc testing.mdc flutter_widgets.mdc \
   ui_ux_design.mdc rules_index.mdc \
   /seu-projeto/.cursor/rules/

# 3. Copie e adapte as regras específicas
cp project_specifics.mdc /seu-projeto/.cursor/rules/

# 4. Edite project_specifics.mdc no seu editor
code /seu-projeto/.cursor/rules/project_specifics.mdc
```

---

**Última atualização**: Março 2026
**Versão Dart/Flutter**: Dart 3.10+, Flutter 3.19+
**Baseado em**: Effective Dart 2026, Flutter AI Rules, Clean Architecture, SOLID Principles
