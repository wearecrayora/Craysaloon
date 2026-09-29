import { requireAdmin } from '@/server/auth';
import { getAccessRequestExport } from '@/server/admin-db';

/**
 * A customer's copy of their data (DPDP s.11), produced by REQUEST id - the
 * console is never given a way to look a person up (0081), only to answer a
 * request they made. A download, never a page, and never cached.
 */
export const dynamic = 'force-dynamic';

export async function GET(_req: Request, { params }: { params: Promise<{ requestId: string }> }) {
  const { requestId } = await params;
  const admin = await requireAdmin();

  let body: unknown;
  try {
    body = await getAccessRequestExport(admin.id, requestId);
  } catch {
    return new Response('That is not an open request for a copy of someone’s data.', { status: 404 });
  }

  return new Response(JSON.stringify(body, null, 2), {
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'content-disposition': `attachment; filename="your-data-${requestId}.json"`,
      'cache-control': 'no-store',
    },
  });
}
