const pkg = require('cloudinary');
const cloudinary = pkg.v2 || pkg;

function initCloudinaryFromEnv() {
  try {
    if (process.env.CLOUDINARY_URL) {
      // cloudinary will read CLOUDINARY_URL automatically, but ensure secure true
      cloudinary.config({ secure: true });
      return true;
    }
    const { CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET } = process.env;
    if (CLOUDINARY_CLOUD_NAME && CLOUDINARY_API_KEY && CLOUDINARY_API_SECRET) {
      cloudinary.config({
        cloud_name: CLOUDINARY_CLOUD_NAME,
        api_key: CLOUDINARY_API_KEY,
        api_secret: CLOUDINARY_API_SECRET,
        secure: true,
      });
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}

async function uploadLocalFile(filePath, options = {}) {
  if (!filePath) throw new Error('filePath required');
  const res = await cloudinary.uploader.upload(filePath, options);
  return res;
}

function generateSignature(params = {}) {
  // params is an object of parameters to include in the signature (e.g. {folder: 'x'})
  const ts = Math.floor(Date.now() / 1000);
  const toSign = Object.assign({}, params, { timestamp: ts });
  const apiSecret = process.env.CLOUDINARY_API_SECRET;
  if (!apiSecret) throw new Error('CLOUDINARY_API_SECRET not configured');
  const signature = cloudinary.utils.api_sign_request(toSign, apiSecret);
  return { signature, timestamp: ts, api_key: process.env.CLOUDINARY_API_KEY, cloud_name: process.env.CLOUDINARY_CLOUD_NAME };
}

module.exports = {
  initCloudinaryFromEnv,
  uploadLocalFile,
  generateSignature,
};
