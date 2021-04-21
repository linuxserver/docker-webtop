# Contributing to webtop

## Gotchas

* While contributing make sure to make all your changes before creating a Pull Request, as our pipeline builds each commit after the PR is open.
* Read, and fill the Pull Request template
  * If this is a fix for a typo in code or documentation in the README please file an issue
  * If the PR is addressing an existing issue include, closes #\<issue number>, in the body of the PR commit message
* If you want to discuss changes, you can also bring it up in [#dev-talk](https://discordapp.com/channels/354974912613449730/757585807061155840) in our [Discord server](https://discord.gg/YWrKVTn)

## Common files

| File | Use case |
| :----: | --- |
| `Dockerfile` | Dockerfile used to build amd64 images |
| `Dockerfile.aarch64` | Dockerfile used to build 64bit ARM architectures |
| `Dockerfile.armhf` | Dockerfile used to build 32bit ARM architectures |
| `Jenkinsfile` | This file is a product of our builder and should not be edited directly. This is used to build the image |
| `jenkins-vars.yml` | This file is used to generate the `Jenkinsfile` mentioned above, it only affects the build-process |
| `package_versions.txt` | This file is generated as a part of the build-process and should not be edited directly. It lists all the installed packages and their versions |
| `README.md` | This file is a product of our builder and should not be edited directly. This displays the readme for the repository and image registries |
| `readme-vars.yml` | This file is used to generate the `README.md` |

## Readme

If you would like to change our readme, please __**do not**__ directly edit the readme, as it is auto-generated on each commit.
Instead edit the [readme-vars.yml](https://github.com/linuxserver/docker-webtop/edit/alpine-kde/readme-vars.yml).

These variables are used in a template for our [Jenkins Builder](https://github.com/linuxserver/docker-jenkins-builder) as part of an ansible play.
Most of these variables are also carried over to [docs.linuxserver.io](https://docs.linuxserver.io/images/docker-webtop)

### Fixing typos or clarify the text in the readme

There are variables for multiple parts of the readme, the most common ones are:

| Variable | Description |
| :----: | --- |
| `project_blurb` | This is the short excerpt shown above the project logo. |
| `app_setup_block` | This is the text that shows up under "Application Setup" if enabled |

### Parameters

The compose and run examples are also generated from these variables.

We have a [reference file](https://github.com/linuxserver/docker-jenkins-builder/blob/master/vars/_container-vars-blank) in our Jenkins Builder.

These are prefixed with `param_` for required parameters, or `opt_param` for optional parameters, except for `cap_add`.
Remember to enable param, if currently disabled. This differs between parameters, and can be seen in the reference file.

Devices, environment variables, ports and volumes expects its variables in a certain way.

### Devices

```yml
param_devices:
  - { device_path: "/dev/dri", device_host_path: "/dev/dri", desc: "For hardware transcoding" }
opt_param_devices:
  - { device_path: "/dev/dri", device_host_path: "/dev/dri", desc: "For hardware transcoding" }
```

### Environment variables

```yml
param_env_vars:
  - { env_var: "TZ", env_value: "Europe/London", desc: "Specify a timezone to use EG Europe/London." }
opt_param_env_vars:
  - { env_var: "VERSION", env_value: "latest", desc: "Supported values are LATEST, PLEXPASS or a specific version number." }
```

### Ports

```yml
param_ports:
  - { external_port: "80", internal_port: "80", port_desc: "Application WebUI" }
opt_param_ports:
  - { external_port: "80", internal_port: "80", port_desc: "Application WebUI" }
```

### Volumes

```yml
param_volumes:
  - { vol_path: "/config", vol_host_path: "</path/to/appdata/config>", desc: "Configuration files." }
opt_param_volumes:
  - { vol_path: "/config", vol_host_path: "</path/to/appdata/config>", desc: "Configuration files." }
```

### Testing template changes

After you make any changes to the templates, you can use our [Jenkins Builder](https://github.com/linuxserver/docker-jenkins-builder) to have the files updated from the modified templates. Please use the command found under `Running Locally` [on this page](https://github.com/linuxserver/docker-jenkins-builder/blob/master/README.md) to generate them prior to submitting a PR.

## Dockerfiles

We use multiple Dockerfiles in our repos, this is because sometimes some CPU architectures needs different packages to work.
If you are proposing additional packages to be added, ensure that you added the packages to all the Dockerfiles in alphabetical order.

### Testing your changes

```bash
git clone https://github.com/linuxserver/docker-webtop.git
cd docker-webtop
docker build \
  --no-cache \
  --pull \
  -t linuxserver/webtop:latest .
```

The ARM variants can be built on x86_64 hardware using `multiarch/qemu-user-static`

```bash
docker run --rm --privileged multiarch/qemu-user-static:register --reset
```

Once registered you can define the dockerfile to use with `-f Dockerfile.aarch64`.

## Update the changelog

If you are modifying the Dockerfiles or any of the startup scripts in [root](https://github.com/linuxserver/docker-webtop/tree/alpine-kde/root), add an entry to the changelog

```yml
changelogs:
  - { date: "DD.MM.YY:", desc: "Added some love to templates" }
```
