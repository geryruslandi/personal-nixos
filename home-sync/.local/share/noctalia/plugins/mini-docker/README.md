# Mini Docker

Mini Docker manages Docker containers, images, volumes, and networks from
Noctalia. Its bar widget shows the number of running containers while Docker is
reachable, while its panel provides common management actions.

This is a local fork of the community plugin `8bury/mini-docker`, re-authored as
`gery/mini-docker`. The bar icon and running counter use the `gery/services` hub
status palette (green running, red stopped); the widget hides itself while the
Docker daemon/socket is unreachable, and the container rows can open a terminal
to follow logs or exec into a shell.

## Plugin

| Field | Value |
| --- | --- |
| ID | `gery/mini-docker` |
| Entries | Bar widget: `mini-docker`; panel: `manager`; service: `docker-service` |

## Requirements

Install the Docker `docker` CLI and make sure your user can connect to the
Docker daemon. Test that `docker info` succeeds without unexpected prompts.

## Usage

Add the `mini-docker` widget to a bar. Left-click it to open the management
panel and right-click it to refresh Docker state immediately.

Open the panel directly with:

```sh
noctalia msg panel-toggle gery/mini-docker:manager
```

The panel has four tabs:

- **Containers:** start, stop, restart, remove, follow logs (`docker logs -f`)
  and open a shell (`docker exec -it`) in a terminal.
- **Images:** run images with an optional name, network, published port, and
  environment variables; remove images that are not in use.
- **Volumes:** inspect and remove volumes.
- **Networks:** inspect and remove non-default networks.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `refresh_interval` | `int` | `5` | Seconds between Docker state refreshes. |
| `default_network` | `string` | `bridge` | Network initially selected when running an image. |
| `container_shell` | `string` | `sh` | Shell used by the container "Shell" action. |
| `logs_tail` | `string` | `200` | Recent lines shown when following container logs. |
| `show_count` | `bool` | `true` | Shows the running-container count in the widget. |
| `status_mode` | `select` | `always` | Shows the status dot always, only while running, or never. |

## Notes

The **Logs** and **Shell** actions open in the terminal returned by
`noctalia.runInTerminal` (`$TERMINAL`, otherwise a terminal discovered on
`PATH`). **Shell** is only enabled for running containers.

Mini Docker runs the local Docker CLI with your user's existing daemon access.
Destructive actions require confirmation in the panel. It does not request
elevated privileges, store Docker credentials, mount host paths, or expose
ports unless you explicitly configure a port while running an image.

