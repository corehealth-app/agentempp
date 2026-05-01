import type { Metadata } from 'next'
import { Fraunces } from 'next/font/google'
import { GeistSans } from 'geist/font/sans'
import { GeistMono } from 'geist/font/mono'
import { Toaster } from '@/components/ui/toaster'
import './globals.css'

const fraunces = Fraunces({
  subsets: ['latin'],
  variable: '--font-display',
  weight: ['400', '500', '600', '700'],
  display: 'swap',
})

export const metadata: Metadata = {
  title: 'Agente MPP — Admin',
  description: 'Painel de controle do Agente MPP — método Muscular Power Plant',
  icons: { icon: '/favicon.ico' },
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html
      lang="pt-BR"
      suppressHydrationWarning
      className={`${fraunces.variable} ${GeistSans.variable} ${GeistMono.variable}`}
      style={
        {
          ['--font-sans' as string]: GeistSans.style.fontFamily,
          ['--font-mono' as string]: GeistMono.style.fontFamily,
        } as React.CSSProperties
      }
    >
      <body className="min-h-screen bg-background text-foreground font-sans paper antialiased">
        {children}
        <Toaster
          theme="light"
          toastOptions={{
            style: {
              background: 'hsl(var(--card))',
              color: 'hsl(var(--foreground))',
              border: '1px solid hsl(var(--border))',
              borderRadius: '4px',
              fontFamily: 'var(--font-sans)',
            },
          }}
        />
      </body>
    </html>
  )
}
