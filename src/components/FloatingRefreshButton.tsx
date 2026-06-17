import { useState } from 'react';
import { RefreshCw } from 'lucide-react';

type Props = {
  onRefresh: () => void | Promise<void>;
  label?: string;
};

export function FloatingRefreshButton({ onRefresh, label = 'Atualizar' }: Props) {
  const [spinning, setSpinning] = useState(false);

  const handleClick = async () => {
    if (spinning) return;
    setSpinning(true);
    try {
      await onRefresh();
    } finally {
      // Garante feedback visual mesmo se o fetch for muito rápido.
      setTimeout(() => setSpinning(false), 500);
    }
  };

  return (
    <button
      onClick={handleClick}
      aria-label={label}
      className="fixed bottom-20 right-4 z-40 h-11 w-11 rounded-full glass-card border border-border/60 shadow-lg flex items-center justify-center text-foreground/80 hover:text-foreground hover:scale-105 active:scale-95 transition-all disabled:opacity-60"
      disabled={spinning}
    >
      <RefreshCw className={`h-5 w-5 ${spinning ? 'animate-spin' : ''}`} strokeWidth={2.25} />
    </button>
  );
}
