import * as React from "react";
import { cn } from "@/lib/utils";
import { Loader2 } from "lucide-react";

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "outline" | "ghost" | "danger";
  size?: "sm" | "md" | "lg" | "icon";
  loading?: boolean;
}

const variantClasses: Record<NonNullable<ButtonProps["variant"]>, string> = {
  primary:
    "bg-[#4B83F5] text-white hover:bg-[#3B72E4] active:scale-[0.98] border border-blue-400/30 shadow-[0_0_16px_rgba(75,131,245,0.25)] focus-visible:ring-[#4B83F5]",
  secondary:
    "bg-[rgba(45,53,65,0.7)] text-[#F2F4F8] hover:bg-[rgba(55,65,78,0.85)] active:scale-[0.98] border border-[rgba(190,205,225,0.18)] shadow-sm focus-visible:ring-[rgba(190,205,225,0.3)] backdrop-blur-sm",
  outline:
    "bg-[rgba(23,28,36,0.6)] text-[#F2F4F8] hover:bg-[rgba(35,42,53,0.85)] active:scale-[0.98] border border-[rgba(190,205,225,0.20)] shadow-xs focus-visible:ring-[rgba(190,205,225,0.3)]",
  ghost:
    "bg-transparent text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8] active:scale-[0.98] border border-transparent focus-visible:ring-white/20",
  danger:
    "bg-[#E56B72] text-white hover:bg-[#D5575E] active:scale-[0.98] border border-red-400/30 shadow-[0_0_14px_rgba(229,107,114,0.25)] focus-visible:ring-[#E56B72]",
};

const sizeClasses: Record<NonNullable<ButtonProps["size"]>, string> = {
  sm: "h-8 px-3 text-xs font-medium rounded-lg gap-1.5",
  md: "h-10 px-4 text-sm font-medium rounded-xl gap-2",
  lg: "h-11 px-5 text-sm font-semibold rounded-xl gap-2",
  icon: "h-9 w-9 p-0 rounded-xl",
};

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  (
    {
      className,
      variant = "primary",
      size = "md",
      loading = false,
      disabled,
      children,
      type = "button",
      ...props
    },
    ref
  ) => {
    return (
      <button
        ref={ref}
        type={type}
        disabled={disabled || loading}
        className={cn(
          "inline-flex items-center justify-center whitespace-nowrap transition-all duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-1 focus-visible:ring-offset-[#101318] disabled:pointer-events-none disabled:opacity-40 cursor-pointer font-medium",
          variantClasses[variant],
          sizeClasses[size],
          className
        )}
        {...props}
      >
        {loading && <Loader2 className="h-4 w-4 animate-spin shrink-0" />}
        {children}
      </button>
    );
  }
);
Button.displayName = "Button";
