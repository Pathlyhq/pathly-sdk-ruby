# Pathly Ruby SDK

[English](README.md) · [Français](README.fr.md) · **Español**


[![Powered by Pathly](https://img.shields.io/badge/Powered%20by-Pathly-0B5FFF?style=flat-square)](https://pathlyhq.com)
[![Website](https://img.shields.io/badge/Website-pathlyhq.com-111827?style=flat-square)](https://pathlyhq.com)
[![API docs](https://img.shields.io/badge/API-developers-2563eb?style=flat-square)](https://pathlyhq.com/es/developers)
[![Start free](https://img.shields.io/badge/Solo-start%20free-16a34a?style=flat-square)](https://pathlyhq.com/es/login?mode=signup)

> **Empiece en un clic.** Cree una cuenta gratuita en [Pathly](https://pathlyhq.com) ([registro](https://pathlyhq.com/es/login?mode=signup)), genere una clave API en la consola y exporte `PATHLY_API_TOKEN`. Este repositorio es el puente oficial hacia [la monitorización Pathly](https://pathlyhq.com): comprobaciones HTTP y de navegador (carrito, login, disponibilidad), con datos en la UE. Referencia API: [pathlyhq.com/es/developers](https://pathlyhq.com/es/developers).

> **La versión en inglés es la referencia.** Este documento traduce [`README.md`](README.md).

Cliente Ruby oficial de la API pública [Pathly](https://pathlyhq.com) `/v1`.
Gestione escenarios de monitorización HTTP, ventanas de mantenimiento, webhooks
firmados de salida y objetivos SLA desde scripts, trabajos Sidekiq y CI.

Sitio del producto: [pathlyhq.com](https://pathlyhq.com). Referencia API y auth:
[pathlyhq.com/es/developers](https://pathlyhq.com/es/developers).

```bash
gem install pathly
export PATHLY_API_TOKEN="sp_…"
```

```ruby
require "pathly"

client = Pathly::Client.new  # reads PATHLY_API_TOKEN
scenario = client.create_scenario(
  name: "Checkout",
  url: "https://shop.example.com/cart",
  intervalSec: 300,
  expectText: "Your cart",
  tags: %w[prod payment]
)
puts scenario["id"]
```


## Autenticación

| Variable | Propósito |
|---|---|
| `PATHLY_API_TOKEN` | Clave de API de la organización (prefijo `sp_`). Obligatoria. |
| `PATHLY_API_URL` | Base de la API. Por defecto `https://api.pathlyhq.com`. |

Nunca codifique el token en el control de versiones. Prefiera el entorno, o un
almacén de secretos inyectado en tiempo de ejecución. Lista completa de scopes:
[desarrolladores](https://pathlyhq.com/es/developers).

### Scopes mínimos

| Grupo de métodos | Scopes |
|---|---|
| Escenarios | `scenarios:read`, `scenarios:write` |
| Webhooks | `alerting:read`, `alerting:write` |
| Ventanas de mantenimiento | `maintenance:read`, `maintenance:write` |
| Objetivos SLA | `sla:read`, `sla:write` |

`Client#ping` llama a `/v1/usage` y **acepta HTTP 403**: la clave es válida pero
carece de `org:read`. Así se mantiene el menor privilegio para claves solo de
escenarios.

## Qué gestiona este SDK

| Recurso | Métodos |
|---|---|
| Escenario (HTTP) | `create_scenario`, `get_scenario`, `update_scenario`, `delete_scenario`, `list_scenarios`, `mute_scenario` |
| Ventana de mantenimiento | `create_maintenance_window`, `get_maintenance_window`, `delete_maintenance_window`, `list_maintenance_windows` |
| Webhook | `create_webhook`, `get_webhook`, `delete_webhook`, `list_webhooks` |
| Objetivo SLA | `upsert_sla_target`, `get_sla_target`, `delete_sla_target`, `list_sla_targets` |

Los recorridos de navegador **no** se gestionan aquí: sus pasos llevan
credenciales de acceso que acabarían en logs o tickets. Créelos en la
[consola Pathly](https://pathlyhq.com).

El **secret** del webhook se devuelve una sola vez en la creación. Guárdelo en
un vault de inmediato. La API nunca devuelve la URL de destino en lectura, solo
`urlFingerprint`.

## Comportamiento

- Las creaciones envían un `Idempotency-Key` (UUID generado automáticamente salvo que pase uno).
- HTTP 429 y 5xx respetan `Retry-After` (tope de 90 segundos, cuatro intentos).
- HTTP 404 lanza `Pathly::NotFoundError` (helper `Pathly.not_found?(err)`).
- Sin dependencias de runtime de terceros (solo stdlib `net/http`).

## Desarrollo

```bash
bundle install
bundle exec rspec
```

Se exige cobertura al **100%** (SimpleCov).

## Paquetes relacionados

| Paquete | Rol |
|---|---|
| [pathly-sdk-python](https://github.com/pathlyhq/pathly-sdk-python) | Python `pathly` |
| [pathly-sdk-typescript](https://github.com/pathlyhq/pathly-sdk-typescript) | `@pathlyhq/sdk` |
| [pathly-postman](https://github.com/pathlyhq/pathly-postman) | Postman / OpenAPI explorers |
| [pathly-terraform-provider](https://github.com/pathlyhq/pathly-terraform-provider) | Terraform / OpenTofu |

Referencia API: [pathlyhq.com/es/developers](https://pathlyhq.com/es/developers).

## Acerca de Pathly

[Pathly](https://pathlyhq.com) es monitorización sintética para agencias y e-commerce: reproduce el recorrido del cliente, detecta un checkout roto antes de la llamada, y deja la prueba (captura, paso, runbook) lista para la factura. Producto: [pathlyhq.com](https://pathlyhq.com) · Desarrolladores: [pathlyhq.com/es/developers](https://pathlyhq.com/es/developers) · Precios: [pathlyhq.com/es/pricing](https://pathlyhq.com/es/pricing).

## Autor

| | |
|---|---|
| **Empresa** | Pathly |
| **Autor** | Simon Raynaud / keyral |

Véase [AUTHORS](AUTHORS).

## Licencia
Apache-2.0
