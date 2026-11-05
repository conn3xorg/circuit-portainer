# Local example

Applies circuit-portainer to a throwaway Rocky Linux 10 container with systemd: the Portainer server and an agent on the same host. You need Conn3x, Podman and Python 3.

Portainer runs under Podman inside that container, so the host container is privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The first apply takes a few minutes: it installs Podman, turns on its API socket and pulls both images. The second plan says `No changes.` The admin password and the agent secret are defaults in `main.tf`, which you'd never keep on a real host.

Then run the check CI runs:

```sh
./check.sh
```

It copies Portainer's self-signed certificate out of the container, opens an SSH tunnel to `127.0.0.1:9443`, signs in as `admin`, lists the containers through Podman, and adds the agent as a second environment. To look around yourself, forward the port and open `https://localhost:9443`:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts -L 9443:127.0.0.1:9443 root@127.0.0.1
```

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT` and to `check.sh` as `PORT`. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
