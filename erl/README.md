# Erlang / rebar3 installation
Instructions for **rebar3** installation on Windows and Linux. A short tutorial explaining how to create a new project with a Cowboy dependency is also present.

rebar3 is needed to support the *Erlang* modules of this project.
## Windows

<details>
<summary>Erlang and rebar3 installation in Windows</summary>

### Erlang/OTP
Download Erlang from the official website
### Rebar3
These instructions are taken from this tutorial 
[Youtube tutorial](https://www.youtube.com/watch?v=mn3fso1SIaw) by [Ryudith](https://www.youtube.com/@Ryudith)
1) Create a folder to host rebar3: for the example we'll use `C:\rebar3`
2) Download rebar3 from official website: [rebar3.org](https://rebar3.org)
    - Move the downloaded file `rebar3` into the rebar folder
3) In the rebar folder create an empty file named `rebar3.cmd`
4) Write these lines into the file:
    ```cmd
    @echo off
    setlocal
    set rebarscript=%~f0
    escript.exe "%rebarscript:.cmd=%" %*
    ```
5) Create an empty folder into the main `C:\rebar3` folder, call it `libs`
    - So you will have a folder `C:\rebar3\libs`
6) Add rebar to the PATH system environment variable
7) Create a new environment variable for the rebar3 cache:
    - New (system) variable
        - Variable name: `REBAR_CACHE_DIR`
        - Variable value: `C:\rebar3\libs`
        
Open a command prompt and type `rebar3 --help` to check that everything is working properly

</details>

## Linux
<details>
<summary>Erlang and rebar3 installation in Linux</summary>


This method has been tested on Ubuntu-24.04 .
### Erlang/OTP
```bash
sudo apt update
sudo apt install erlang
```
### Rebar3
rebar3 is needed for creating the Erlang envirnoment with Cowboy.
##### Method 1
1) Install latest release of rebar3:
    ```bash
    wget https://s3.amazonaws.com/rebar3/rebar3
    ```
3) A folder named `rebar3` will be downloaded:
    ```bash
    chmod +x rebar3
    sudo mv rebar3 /usr/local/bin/
    ```
3) Check if it is compatible with Erlang/OTP installed:
    ```bash
    rebar3 --version
    ```
    It should print something like `rebar 3.27.0+...`
    
##### Method 2
This method can be used if the previous one is not working, in particular if the Erlang and rebar3 versions do not correspond. With this method you install the bootstrap version of rebar, then compile it to your (installed) version of Erlang/OTP.

1) Download the bootstrap version of rebar
    ```bash
    git clone https://github.com/erlang/rebar3.git
    ```
2) Compile it to your version of Erlan/OTP
    ```bash
    cd rebar3
    ./bootstrap
    ```
3) A folder named `rebar3` will be created, move to bin:
    ```bash
    sudo mv rebar3 /usr/local/bin/
    ```
    
</details>

## *extra* - Create new Erlang project with Cowboy
These are the instructions to follow to create a new project with a Cowboy dependency using rebar3, once installed.
1) Create a project with rebar:
    ```bash
    rebar3 new app app_name
    cd app_name
    ```
2) Add cowboy dependency to `rebar.config`:
    ```bash
    {deps, [
        {cowboy, "2.10.0"}
    ]}.
    ```
3) Download dependencies:
    ```bash
    rebar3 get-deps
    rebar3 compile
    ```
4) Compile the project:
    ```bash
    rebar3 compile
    ```
5) Run the application
    ```bash
    rebar3 shell
    ```
