# Ícones do Sistema de Backup

Este diretório contém todos os ícones utilizados no **Sistema de Backup de Bancos de Dados** (SQL Server e Sybase SQL Anywhere).

## 📋 Visão Geral

O sistema é uma aplicação Flutter Desktop para Windows que realiza backups automáticos de bancos SQL Server e Sybase ASA, com suporte a múltiplos destinos (Local, FTP, Google Drive) e notificações por e-mail.

## 🎯 Ícones Necessários

### 1. System Tray Icon (`tray_icon.ico` e `tray_icon.png`)

**Propósito**: Ícone exibido na bandeja do sistema (System Tray) do Windows quando a aplicação está minimizada.

**Uso**: 
- Configurado através do `tray_manager` package
- Permanece visível mesmo com a janela minimizada
- Permite restaurar a janela, executar backup manual ou sair via menu de contexto
- Deve refletir o status do sistema (ex: animação durante backup)

**Especificações Técnicas**:

**tray_icon.ico** (Windows):
- Arquivo `.ico` multi-resolução obrigatório
- Dimensões necessárias:
  - 16x16 pixels (tamanho pequeno na bandeja)
  - 32x32 pixels (tamanho médio)
  - 48x48 pixels (tamanho grande)
  - 256x256 pixels (alta resolução para DPI escalado)

**tray_icon.png** (Fallback):
- Versão PNG para compatibilidade
- Tamanho recomendado: 256x256 pixels
- Fundo transparente

**Diretrizes de Design**:
- Tema: Backup de banco de dados (SQL Server/Sybase)
- Elementos sugeridos:
  - Disco rígido ou cilindro de banco de dados
  - Seta indicando backup/cópia
  - Nuvem (opcional, representando destinos remotos)
- Cores:
  - Paleta profissional (azul/verde para sucesso, laranja/vermelho para alertas)
  - Contraste adequado para fundo claro e escuro do Windows
  - Considere versões para diferentes estados (normal, backup em andamento, erro)
- Estilo:
  - Simples e minimalista
  - Reconhecível mesmo em 16x16 pixels
  - Ícone flat ou com sombra sutil
  - Fundo transparente obrigatório

**Como criar**:

1. Criar o design no Figma, Photoshop, Illustrator ou similar
2. Exportar como PNG em múltiplos tamanhos (16x16, 32x32, 48x48, 256x256)
3. Converter para `.ico` usando ferramenta online:
   - https://www.icoconverter.com/
   - https://convertio.co/png-ico/
   - https://icoconvert.com/
4. Verificar visualização em diferentes tamanhos
5. Substituir o arquivo `tray_icon.ico` nesta pasta

---

### 2. Favicon (`favicon.ico`)

**Propósito**: Ícone exibido na aba do navegador (se aplicável) e identificação geral da aplicação.

**Especificações**:
- Arquivo `.ico` com múltiplas resoluções
- Dimensões: 16x16, 32x32, 48x48 pixels
- Mesmo design do ícone principal, adaptado para tamanhos menores

**Status**: ✅ Já existe no diretório

---

### 3. Ícone da Aplicação - 512x512

**Propósito**: Ícone principal da aplicação usado na instalação, atalhos e identificação do executável.

#### 3.1 `icon-512-maskable.png`

**Especificações**:
- Formato: PNG
- Dimensão: 512x512 pixels
- Background: Transparente ou cor sólida
- Uso: Ícone padrão para diferentes contextos

**Status**: ✅ Já existe no diretório

#### 3.2 `icon-512-dark.svg`

**Especificações**:
- Formato: SVG (vetorial)
- Dimensão: 512x512 pixels (viewport)
- Background: Otimizado para temas escuros
- Uso: Ícone adaptado para interface dark mode

**Status**: ✅ Já existe no diretório

#### 3.3 `icon-512-embedded.svg`

**Especificações**:
- Formato: SVG (vetorial)
- Dimensão: 512x512 pixels (viewport)
- Background: Otimizado para embedding
- Uso: Ícone para embedding em documentos ou web

**Status**: ✅ Já existe no diretório

---

## 🎨 Diretrizes de Design Unificadas

### Tema Visual

O sistema de backup deve transmitir:
- **Confiabilidade**: Design sólido e profissional
- **Segurança**: Cores e símbolos que remetam à proteção de dados
- **Eficiência**: Visual limpo e objetivo
- **Profissionalismo**: Adequado para ambientes corporativos e servidores

### Elementos Visuais Sugeridos

**Ícones de Backup**:
- Cilindro de banco de dados (SQL Server/Sybase)
- Disco rígido ou storage
- Seta circular indicando backup/restauração
- Nuvem (para destinos remotos)
- Badge de status (verde=sucesso, vermelho=erro, amarelo=pendente)

**Paleta de Cores**:
- **Primária**: Azul (#2196F3, #1976D2) - Confiança, tecnologia
- **Sucesso**: Verde (#4CAF50, #388E3C) - Backup concluído
- **Erro**: Vermelho (#F44336, #D32F2F) - Falha no backup
- **Aviso**: Laranja (#FF9800, #F57C00) - Alertas e pendências
- **Neutro**: Cinza (#757575, #616161) - Estados inativos

### Requisitos de Acessibilidade

- Contraste mínimo de 4.5:1 para texto/background
- Reconhecível em escala de cinza
- Funcional em tamanhos pequenos (16x16 pixels)
- Distinguível mesmo com deficiência de cor

---

## 📁 Estrutura de Arquivos Esperada

```
assets/icons/
├── favicon.ico                    # Favicon (16x16, 32x32, 48x48)
├── icon-512-maskable.png         # Ícone principal 512x512 (PNG)
├── icon-512-dark.svg             # Ícone para dark mode (SVG)
├── icon-512-embedded.svg         # Ícone para embedding (SVG)
├── tray_icon.ico                 # Ícone system tray Windows (.ico multi-resolução)
├── tray_icon.png                 # Fallback system tray (256x256 PNG)
└── README.md                     # Esta documentação
```

---

## 🔧 Configuração no Projeto

### System Tray

O ícone do system tray é configurado através do `tray_manager` package:

```dart
// presentation/managers/tray_manager.dart
await trayManager.setIcon(
  'assets/icons/tray_icon.ico', // Windows
  'assets/icons/tray_icon.png', // Fallback
);
```

### Ícone da Aplicação

Os ícones principais são configurados no `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/icons/
  
flutter_launcher_icons:
  windows:
    image_path: "assets/icons/icon-512-maskable.png"
    icon_size: 512
```

---

## ✅ Checklist de Ícones

- [x] `favicon.ico` - Já existe
- [x] `icon-512-maskable.png` - Já existe
- [x] `icon-512-dark.svg` - Já existe
- [x] `icon-512-embedded.svg` - Já existe
- [ ] `tray_icon.ico` - **Pendente de criação**
- [ ] `tray_icon.png` - **Pendente de criação**

---

## 📝 Notas Importantes

1. **Compatibilidade Windows**: O formato `.ico` é obrigatório para o system tray no Windows
2. **DPI Scaling**: Sempre forneça múltiplas resoluções para suportar diferentes escalas de DPI
3. **Fundo Transparente**: Todos os ícones devem ter fundo transparente para melhor integração
4. **Testes**: Teste os ícones em diferentes tamanhos e contextos antes de finalizar
5. **Versões de Estado**: Considere criar variações para diferentes estados (normal, backup em andamento, erro)

---

## 🔗 Recursos Úteis

### Ferramentas de Conversão
- [ICO Converter](https://www.icoconverter.com/)
- [Convertio](https://convertio.co/png-ico/)
- [ICO Convert](https://icoconvert.com/)

### Ferramentas de Design
- [Figma](https://www.figma.com/) - Design colaborativo
- [IconKitchen](https://icon.kitchen/) - Gerador de ícones
- [RealFaviconGenerator](https://realfavicongenerator.net/) - Gerador de favicons

### Bibliotecas de Ícones
- [Flutter Icons](https://pub.dev/packages/flutter_launcher_icons)
- [Material Icons](https://fonts.google.com/icons)

