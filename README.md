# xamxam
BASH script to automate Xamarin root/jailbreak/cert pinning restriction removal.
Downloads apktool and uber-signer .jar files, creates a pyxamstore venv (due to old requirements), patches Solo.dll with xxd, repacks and signs ready for install (hopefully).

```
Usage: xamxam.sh {input-file} {output-file}
```
