import { requireAdmin } from '@/server/auth';
import { getSalonExport } from '@/server/admin-db';

/**
 * The owner's export: everything the salon holds, as one JSON file (M12).
 *
 * A download, not a page, so it never sits in a browser history or a cache as
 * rendered HTML. The database refuses anyone but a super-admin. Downloading it
 * records nothing - "offered to the owner" is a separate, deliberate record,
 * because producing a file is not the same as giving it to someone.
 */
export const dynamic = 'force-dynamic';

export async function GET(_req: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const admin = await requireAdmin();

  let body: unknown;
  try {
    body = await getSalonExport(admin.id, id);
  } catch {
    return new Response('Only a Crayora super-admin can export a salon.', { status: 403 });
  }
  if (!body) return new Response('No such salon.', { status: 404 });

  const date = new Date().toISOString().slice(0, 10);
  return new Response(JSON.stringify(body, null, 2), {
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'content-disposition': `attachment; filename="salon-export-${id}-${date}.json"`,
      'cache-control': 'no-store',
    },
  });
}
