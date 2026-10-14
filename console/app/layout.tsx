import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Crayora Console',
  description: 'Provision and operate Cray Salon tenants.',
  robots: { index: false, follow: false },
  // Without it every page asked for /favicon.ico and got a 404.
  icons: { icon: '/icon-64.png' },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
