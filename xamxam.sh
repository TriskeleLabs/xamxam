#!/bin/bash

if [[ -z "$1" ]] || [[ -z "$2" ]]; then
        echo "[-] APK input and output filenames required"
        echo "[*] $0 {input.apk} {output.apk}"
        exit
fi

# copy .apk file
apk_file=$1
apk_output_file=$2
temp_dir=$(mktemp -d)
echo "[*] Temp dir: $temp_dir"
cp $apk_file $temp_dir/
cd $temp_dir

# download latest apktool
echo "[*] Downloading: apktool"
apktool_jar=$(curl -s https://api.github.com/repos/iBotPeaches/apktool/releases/latest | jq -r '.assets[0].browser_download_url')
wget $apktool_jar -O apktool.jar

# download latest uber-apk-signer
echo "[*] Downloading: uber-signer"
ubersigner_jar=$(curl -s https://api.github.com/repos/patrickfav/uber-apk-signer/releases/latest | jq -r '.. | objects | .browser_download_url?' | grep '.jar')
wget $ubersigner_jar -O ubersigner.jar

# decompile apk
echo "[*] Decompiling: $apk_file"
java -jar apktool.jar d $apk_file -o decompiled_apk

# download pyxamstore and create venv
echo "[*] Creating pyxamstore venv"
python3 -m venv pyxamvenv
source ./pyxamvenv/bin/activate
git clone https://github.com/jakev/pyxamstore.git
cd ./pyxamstore
pip3 install -r requirements.txt
pip3 install setuptools
python3 setup.py install

# unpack files
echo "[*] Unpacking Xamarin files"
cd ..
pyxamstore unpack -d decompiled_apk/unknown/assemblies/

# back up Solo.dll
#cp ./out/Solo.dll ./Solo.dll.bak

# replace hex
xxd -p -c 1000000 ./out/Solo.dll > ./Solo.dll.hex

echo "[*] Removing iOS/Android enforce"
# ios enforce false
sed -i 's/22656e666f726365694f53223a2074727565/22656e666f726365694f53223a66616c7365/' ./Solo.dll.hex

# android enforce false
sed -i 's/22656e666f726365416e64726f6964223a2074727565/22656e666f726365416e64726f6964223a66616c7365/' ./Solo.dll.hex

# find all instances of "pinnedCertificates": [something] and replace everything between the [ ] with null bytes
echo "[*] Removing cert pinning"
cert_results=$(cat Solo.dll.hex | grep -oP '2270696e6e6564436572746966696361746573223a205b.*?(?=5d)')
for cert_result in $cert_results
do
        cert_text=$(echo "$cert_result" | xxd -r -p)
        echo "[*] Found: $cert_text"
        cert_result_len=${#cert_result}
        echo "[*] Length: $cert_result_len"
        # this is the length of the hex to replace minus the pinnedCertificates bit
        adj_result=$(($cert_result_len - 46))

        # new hex is all 00 between the [] brackets
        new_hex=$(printf "2270696e6e6564436572746966696361746573223a205b")
        new_hex+=$(for i in $(seq 1 $adj_result); do printf '0'; done)
        # new_text=$(echo "$new_hex" | xxd -r -p)
        echo "[*] New: $new_hex"
        sed -i "s/$cert_result/$new_hex/" ./Solo.dll.hex
done

# convert back to hex
xxd -p -r ./Solo.dll.hex ./Solo.new.dll

# replace old Solo.dll
mv Solo.new.dll ./out/Solo.dll

# repack
echo "[*] Repacking Xamarin files"
pyxamstore pack

# replace assemblies.*
echo "[*] Replacing assemblies"
cp ./assemblies.blob.new ./decompiled_apk/unknown/assemblies/assemblies.blob
cp ./assemblies.manifest.new ./decompiled_apk/unknown/assemblies/assemblies.manifest

# repack apk
echo "[*] Repacking apk"
java -jar apktool.jar b -o ./$apk_output_file ./decompiled_apk/

# resign apk
echo "[*] Resigning apk"
java -jar ubersigner.jar --apks ./$apk_output_file

# just file name trimming stuff to make it work
file_minus_extension="${apk_output_file%.apk}"
patched_apk="$file_minus_extension-aligned-debugSigned.apk"
echo "[*] Copying $patched_apk to /tmp"
cp $patched_apk /tmp/

# deactivate venv
echo "[*] Deactivating pyxamstore venv"
deactivate

# delete tmp dir
echo "[*] Deleting $temp_dir"
rm -Rf $temp_dir
