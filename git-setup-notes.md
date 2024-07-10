# Git setup notes

### Basics

[Git](https://git-scm.com) is a distributed version control system. It works by versioning
changes of a folder (the `working copy`) - to store the changes (and other information), it
creates a folder `.git` inside the `working copy` (this is then called a `repository`).

The most common commands to work with the **local** `repository` are:

- `git add <filename>` adds a file to the list of 'monitored' (tracked) files or adds the
  file to the list of files to be used for updating the `repository`. The list of files added
  is called the `staging area` (used for committing, see below)
- `git commit -m <message>` commits changed files into the `repository` to create a new version.
  Please note, that only files from the `stating area` are commited by default, so you will have
  to `git add` them before doing a `git commit`.
- `git status` shows the current state of the (local) repository. You will see if any file
  has changed locally, was added or deleted since the last commit.  
- `git checkout` updates the `working copy` with files from the `repository` (can also be
  used to switch between branches, see [git checkout documentation](https://git-scm.com/docs/git-checkout)). Note that `git` <span style="color:red">never overwrites</span> your data,
  except you force it to - so you might run into warnings about a conflicting changes between the `repository` and your local changes...

The above commands work with the **local** `repository` - for the distributed nature of git, there are additional commands, which handle data exchange and synchronization between multiple
`repositories` (whether they are local, on the internet or on some file server). These commands
work on the `repository` level, they typically don't work on the `working copy` (the files you
see in the folder). The most common commands are:

- `git clone <url>` copies a (possibly remote) `repository` from the given `url` to the local
  filesystem (typically creating a subfolder with the repository name). By default this includes
  the full repository including all versions. The command also (implicitely) checks out and tracks the default branch to populate the `working directory`. In addition it also
  (implicitely) sets up a default `remote` named `origin` to point to the given `url`, so the
  `git push` and `git pull` commands (see below) will automatically synchronize with the
  initially given `url`.
- `git pull <remote-name>` reads the changes from the `<remote-name>` remote repository and
  merges the changes into the local repository. By specifying different `<remote-name>`
  values, changes from different remote repositories can be merged into the local repo.
- `git push <remote-name>` sends changes of the local repository to the `<remote-name>`
  remote repository.
- `git remote` manages the remote connections of the local repository. Typical uses are:
  - `git remote -v` lists the known configured remotes for the local `repository`
  - `git remote add <name> <url>` adds a (remote) `repository` to the local `repository`
       with the given `name`. The `<url>` parameter can either point to a folder (e.g.
       using an UNC path like `\\myserver\myshare`) or to a real URL like `http://...`

A typical use case for working with the samples is:

1. Clone the sample repository to your local machine (to get the latest data). Open a command window, switch to a folder where you want the project data, then run the following commands (must be done only once to setup and initialize your local repo):

    ``` cmd
    @rem Switch to the OGS project folder
    cd "c:\OGS Projects"
    @rem Clone the github repo
    git clone https://github.com/haller-erne/ogs-samples.git
    ```

2. Do some modifications (like changing the `station.ini` parameters). Then run the following to check what has actually changed

    ``` cmd
    @rem Switch to the OGS project "ogs-samples" folder
    cd "c:\OGS Projects\ogs-samples"
    @rem Check the status
    git status
    ```

    This will show all modified, added and deleted files. You cann then select which files
    to commit as follows

    ``` cmd
    @rem Add the changed/added files to the staging are
    git add myfolder/*
    @rem Commit the changes to the local repository
    git commit -m "my changes"
    ```

3. Check for new or modified samples on the server. This works by pulling changes from the
   remote repository into the local repository. Make sure to have all changes commited in your
   local repository before running the following command:

    ``` cmd
    @rem Get all changes from the remote server
    git pull
    ```

    You will see a list of changed files, they will automatically update your local working copy.




### Partial clone

If you are only interested in a specific sample (folder), then you can use the partial clone
feature of git as follows:

``` cmd
@rem Make a new subfolder for the sample projects
mkdir myrepo
cd myrepo
@rem Initialize the GIT folder (repo)
git init .

@rem Add the github server repository as remote
git remote add origin https://github.com/haller-erne/ogs-samples.git
@rem Enable the sparse-checkout feature
git sparse-checkout init
@rem Define the folders to checkout (typically one or more projects)
@rem Note: this is a list of folders, like folder1/subfolder folder2/subfolder
git sparse-checkout set he-007-station-io he-008-positioning
@rem Now actually download the files from the github repo
git fetch --depth=1 origin main
git checkout main
```

### Setting up your own repo to track modifications

Using [git](https://git-scm.com) with multiple [remotes](https://git-scm.com/book/en/v2/Git-Basics-Working-with-Remotes) allows implementing various scenarios including use within
corporate networks with firewall restrictions.

Here is a sample diagram (with setup and usage notes) for a pretty complex case, where the
production systems do not have access to the Internet. To allow versioning of the project
data over multiple station (to ensure all changes are available everywhere), a private git
repository is created on a server in the internal network (`Production server`). This server
only exposes a file share for access to the git repository for the stations. The network admin
can easily define ACLs for the server access (like some groups only have read access), thus
effectively defining which users can push changes from the station to the server and who can
read updated version (pull changes).

![git diagram](./git-setup.drawio.svg)