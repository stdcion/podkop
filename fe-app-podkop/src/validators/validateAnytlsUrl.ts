import { ValidationResult } from './types';
import { parseQueryString } from '../helpers/parseQueryString';

export function validateAnytlsUrl(url: string): ValidationResult {
  try {
    if (!url.startsWith('anytls://')) {
      return {
        valid: false,
        message: _('Invalid AnyTLS URL: must start with anytls://'),
      };
    }

    if (/\s/.test(url)) {
      return {
        valid: false,
        message: _('Invalid AnyTLS URL: must not contain spaces'),
      };
    }

    const body = url.slice('anytls://'.length);

    const [mainPart] = body.split('#');
    const [authHostPort, queryString] = mainPart.split('?');

    if (!authHostPort)
      return {
        valid: false,
        message: _('Invalid AnyTLS URL: missing credentials/server'),
      };

    const [passwordPart, hostPortPart] = authHostPort.split('@');

    if (!passwordPart)
      return {
        valid: false,
        message: _('Invalid AnyTLS URL: missing password'),
      };

    if (!hostPortPart)
      return {
        valid: false,
        message: _('Invalid AnyTLS URL: missing host & port'),
      };

    const [host, port] = hostPortPart.split(':');

    if (!host) {
      return {
        valid: false,
        message: _('Invalid AnyTLS URL: missing host'),
      };
    }

    if (!port) {
      return {
        valid: false,
        message: _('Invalid AnyTLS URL: missing port'),
      };
    }

    const cleanedPort = port.replace('/', '');
    const portNum = Number(cleanedPort);

    if (!Number.isInteger(portNum) || portNum < 1 || portNum > 65535) {
      return {
        valid: false,
        message: _('Invalid AnyTLS URL: invalid port number'),
      };
    }

    if (queryString) {
      const params = parseQueryString(queryString);
      const paramsKeys = Object.keys(params);

      if (
        paramsKeys.includes('insecure') &&
        !['0', '1'].includes(params.insecure)
      ) {
        return {
          valid: false,
          message: _('Invalid AnyTLS URL: insecure must be 0 or 1'),
        };
      }

      if (paramsKeys.includes('sni') && !params.sni) {
        return {
          valid: false,
          message: _('Invalid AnyTLS URL: sni cannot be empty'),
        };
      }
    }

    return { valid: true, message: _('Valid') };
  } catch (_e) {
    return {
      valid: false,
      message: _('Invalid AnyTLS URL: parsing failed'),
    };
  }
}
