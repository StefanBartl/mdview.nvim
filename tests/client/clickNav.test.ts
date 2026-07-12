// tests/client/clickNav.test.ts
import { describe, it, expect } from 'vitest';
import { navTargetFromHref } from '../../src/client/render/clickNav';

describe('navTargetFromHref', () => {
  it('intercepts document-relative links', () => {
    expect(navTargetFromHref('other.md')).toBe('other.md');
    expect(navTargetFromHref('./other.md')).toBe('./other.md');
    expect(navTargetFromHref('../dir/x.md')).toBe('../dir/x.md');
    expect(navTargetFromHref('sub/y.md')).toBe('sub/y.md');
  });

  it('strips fragments and queries', () => {
    expect(navTargetFromHref('other.md#section')).toBe('other.md');
    expect(navTargetFromHref('other.md?x=1')).toBe('other.md');
  });

  it('leaves external and non-navigable links to the browser', () => {
    expect(navTargetFromHref('https://example.com')).toBeNull();
    expect(navTargetFromHref('http://example.com')).toBeNull();
    expect(navTargetFromHref('mailto:a@b.com')).toBeNull();
    expect(navTargetFromHref('//cdn.example.com/x')).toBeNull();
    expect(navTargetFromHref('/root/abs.md')).toBeNull();
    expect(navTargetFromHref('#anchor')).toBeNull();
    expect(navTargetFromHref('')).toBeNull();
    expect(navTargetFromHref(null)).toBeNull();
    expect(navTargetFromHref(undefined)).toBeNull();
  });
});
