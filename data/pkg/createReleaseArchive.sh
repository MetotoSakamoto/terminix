export TERMINIX_ARCHIVE_PATH="/tmp/terminix/archive";

function processPOFile {
    echo "Processing ${1}"
    LOCALE=$(basename "$1" .po)
    mkdir -p ${TERMINIX_ARCHIVE_PATH}/usr/share/locale/${LOCALE}/LC_MESSAGES
    msgfmt $1 -o ${TERMINIX_ARCHIVE_PATH}/usr/share/locale/${LOCALE}/LC_MESSAGES/terminix.mo
}

CURRENT_DIR=$(pwd)

echo "Building application..."
cd ../..
dub build --build=release

echo "Copying resource files..."
cd data/pkg
rm -rf ${TERMINIX_ARCHIVE_PATH}
mkdir -p ${TERMINIX_ARCHIVE_PATH}

mkdir -p ${TERMINIX_ARCHIVE_PATH}/usr/share/glib-2.0/schemas/
cp ../gsettings/com.gexperts.Terminix.gschema.xml ${TERMINIX_ARCHIVE_PATH}/usr/share/glib-2.0/schemas/


export TERMINIX_SHARE=${TERMINIX_ARCHIVE_PATH}/usr/share/terminix

mkdir -p ${TERMINIX_SHARE}/resources
mkdir -p ${TERMINIX_SHARE}/schemes

# Copy and compile icons
cd ../resources
glib-compile-resources terminix.gresource.xml
cp terminix.gresource ${TERMINIX_SHARE}/resources/terminix.gresource
cd ../pkg

# Copy color schemes
cp ../schemes/* ${TERMINIX_SHARE}/schemes

mkdir -p ${TERMINIX_ARCHIVE_PATH}/usr/bin
mkdir -p ${TERMINIX_ARCHIVE_PATH}/usr/share/applications

# Copy executable and desktop file
cp ../../terminix ${TERMINIX_ARCHIVE_PATH}/usr/bin
cp desktop/com.gexperts.Terminix.desktop ${TERMINIX_ARCHIVE_PATH}/usr/share/applications

# Compile po files
echo "Copying and installing localization files"
export -f processPOFile
ls ../../po/*.po | xargs -n 1 -P 10 -I {} bash -c 'processPOFile "$@"' _ {}


echo "Creating archive"
cd ${TERMINIX_ARCHIVE_PATH}
zip -r terminix.zip *

cp terminix.zip ${CURRENT_DIR}/terminix.zip
cd ${CURRENT_DIR}
