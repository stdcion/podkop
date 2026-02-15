export function getProxyUrlName(url: string) {
  if (url === 'direct://') {
    return 'Direct';
  }

  try {
    const [_link, hash] = url.split('#');

    if (!hash) {
      return '';
    }

    return decodeURIComponent(hash);
  } catch {
    return '';
  }
}
