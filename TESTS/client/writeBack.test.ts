import { describe, it, expect } from 'vitest';
import { writeBackUrl } from '../../src/client/render/writeBack';

describe('writeBackUrl', () => {
  it('names the token and the room', () => {
    expect(writeBackUrl('/toggle', { token: 't0k', key: 'C:/n/a.md' })).toBe(
      '/toggle?token=t0k&key=C%3A%2Fn%2Fa.md',
    );
  });

  it('adds the document on screen when there is one', () => {
    expect(writeBackUrl('/edit', { token: 't', key: 'room.md', doc: '/n/other file.md' })).toBe(
      '/edit?token=t&key=room.md&doc=%2Fn%2Fother%20file.md',
    );
  });

  it('leaves doc out when it is unknown or empty', () => {
    expect(writeBackUrl('/field', { token: 't', key: 'k', doc: null })).toBe('/field?token=t&key=k');
    expect(writeBackUrl('/field', { token: 't', key: 'k', doc: '' })).toBe('/field?token=t&key=k');
  });

  it('encodes values that could break the query', () => {
    const url = writeBackUrl('/edit', { token: 'a&b=c', key: 'k#1', doc: 'x?y' });
    expect(url).toBe('/edit?token=a%26b%3Dc&key=k%231&doc=x%3Fy');
  });
});
