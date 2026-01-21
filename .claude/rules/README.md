# Rules (Claude) - Guia de Uso

Este diretório contém regras em Markdown (`.md`) para manter a consistência e qualidade do código. As regras estão organizadas em **genéricas** (reutilizáveis) e **específicas do projeto**.

## 📁 Estrutura dos Arquivos

```
.claude/rules/
├── README.md                 # Este arquivo
├── rules_index.md           # Índice completo das regras
│
├── 🔄 REGRAS GENÉRICAS (Reutilizáveis)
│   ├── general_rules.md         # Regras gerais e princípios fundamentais
│   ├── clean_architecture.md    # Regras genéricas de Clean Architecture (camadas/dependências)
│   ├── solid_principles.md      # Princípios SOLID
│   ├── coding_style.md          # Guia de estilo Dart 2026
│   ├── null_safety.md           # Boas práticas de null safety
│   ├── testing.md               # Padrões de testes
│   ├── flutter_widgets.md       # Widgets Flutter
│   └── ui_ux_design.md          # Princípios de UI/UX para desktop
│
└── 🎯 REGRAS ESPECÍFICAS
    ├── project_specifics.md     # Regras específicas deste projeto (backup_database)
    └── share_app_specifics.md   # Template de outro app (não aplicado aqui)
```

## 🔄 Copiando Regras para Outros Projetos

### 1. Regras Genéricas (Copie TUDO)

Essas regras são **100% reutilizáveis** em qualquer projeto Flutter/Dart:

✅ **Copie estes arquivos sem modificações:**
- `rules_index.md`
- `general_rules.md`
- `clean_architecture.md`
- `solid_principles.md`
- `coding_style.md`
- `null_safety.md`
- `testing.md`
- `flutter_widgets.md`
- `ui_ux_design.md` (se for app desktop)

### 2. Regras Específicas (Adapte)

Este arquivo precisa ser **adaptado** para cada projeto:

⚠️ **Adapte este arquivo:**
- `project_specifics.md` - Ajuste para seu projeto

### Como Adaptar `project_specifics.md`

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
cp -r .claude/rules/*.md /seu-novo-projeto/.claude/rules/

# 2. Edite apenas project_specifics.md
# Ajuste: arquitetura, dependências, estrutura
```

### Para um novo projeto com arquitetura simples:

```bash
# 1. Copie todos os arquivos genéricos
cp -r .claude/rules/*.md /seu-novo-projeto/.claude/rules/

# 2. Simplifique project_specifics.md
# Remova: regras de Clean Architecture, camadas complexas
# Mantenha: dependências, padrões simples
```

## ✨ Conteúdo das Regras Genéricas

### `general_rules.md`
- Princípios fundamentais (código conciso, composição, naming)
- Regras de documentação (não criar docs automáticos)
- Código autoexplicativo
- Evitar números mágicos
- Priorizar componentes reutilizáveis

### `solid_principles.md`
- Single Responsibility Principle (SRP)
- Open/Closed Principle (OCP)
- Liskov Substitution Principle (LSP)
- Interface Segregation Principle (ISP)
- Dependency Inversion Principle (DIP)
- Exemplos e violações comuns

### `coding_style.md`
- Convenções de nomenclatura (2026)
- Declaração de tipos
- Const constructors
- Arrow syntax e expression bodies
- Trailing commas
- Import organization
- Funções e métodos (< 20 linhas)
- Recursos modernos do Dart 3+ (Pattern matching, Records, Switch expressions)

### `null_safety.md`
- Nullable vs non-nullable
- Null-aware operators (`?.`, `??`, `??=`)
- Inicialização de variáveis
- Null checks
- APIs externas

### `testing.md`
- Estrutura de testes (Unit, Widget)
- AAA pattern (Arrange, Act, Assert)
- Nomenclatura de testes
- Mocking e isolamento
- package:checks para assertions

### `flutter_widgets.md`
- Stateless vs Stateful
- Widget composition (private classes, not methods)
- Performance (const, ListView.builder, RepaintBoundary)
- Material 3 theming
- Layout e responsividade
- Tear-offs para widgets

### `ui_ux_design.md`
- Hierarquia visual
- Color palette (60-30-10 rule)
- Typography
- Navegação desktop
- Feedback mechanisms
- Accessibility (WCAG 2.1 AA)
- Responsive design
- Keyboard navigation

## 🎯 Ajustando escopo

Nesta pasta (`.claude/rules`) as regras são apenas referência em Markdown. Se você também usa Cursor, o equivalente em `.cursor/rules/*.mdc` pode ter frontmatter com `globs` para escopo por pastas.

## 📚 Referências

- [Cursor Documentation on Rules](https://docs.cursor.com/en/context/rules)
- [Flutter AI Rules](https://docs.flutter.dev/ai/ai-rules)
- [Effective Dart: Style Guide](https://dart.dev/effective-dart/style)
- [SOLID Principles](https://en.wikipedia.org/wiki/SOLID)
- [Material 3 Guidelines](https://m3.material.io/)

## 🔍 Verificação Rápida

Após copiar as regras para um novo projeto:

- [ ] Todos os arquivos `.md` genéricos foram copiados
- [ ] `project_specifics.md` foi adaptado para o novo projeto
- [ ] Globs foram ajustados se necessário
- [ ] Arquitetura está corretamente documentada
- [ ] Dependências estão listadas
- [ ] Estrutura de pastas está documentada

## 💡 Dicas

1. **Mantenha as regras genéricas sem modificações** - elas são baseadas em best practices
2. **Adapte apenas project_specifics.md** - cada projeto é único
3. **Revise rules_index.md** periodicamente - mantenha atualizado
4. **Mantenha equivalentes em `.cursor/rules`** se você usar Cursor no projeto
5. **Compartilhe conhecimento** - use estas regras como referência para o time

## 🚀 Quick Start para Novo Projeto

```bash
# 1. Crie a pasta de regras
mkdir -p /seu-projeto/.claude/rules

# 2. Copie os arquivos genéricos
cp general_rules.md solid_principles.md coding_style.md \
   null_safety.md testing.md flutter_widgets.md \
   ui_ux_design.md rules_index.md \
   /seu-projeto/.claude/rules/

# 3. Copie e adapte as regras específicas
cp project_specifics.md /seu-projeto/.claude/rules/

# 4. Edite project_specifics.md no seu editor
code /seu-projeto/.claude/rules/project_specifics.md
```

---

**Última atualização**: Janeiro 2026
**Versão Dart/Flutter**: Dart 3+, Flutter 3.19+
**Baseado em**: Effective Dart 2026, Flutter AI Rules, Clean Architecture, SOLID Principles
